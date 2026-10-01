import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'pactl_devices.dart';

/// Reports when the source a capture stream records from goes away.
///
/// The server moves the stream to the fallback source on its own (PulseAudio's
/// module-rescue-streams, WirePlumber on PipeWire), so the monitor remembers
/// the source in use and reports its removal.
class RouteMonitor {
  RouteMonitor({this.pactlBin = 'pactl', this.run = runPactl});

  final String pactlBin;
  final Future<List<String>> Function(List<String> arguments) run;

  Process? _subscribe;
  int? _capturePid;
  int? _source;
  int _generation = 0;
  void Function()? _onRouteLost;
  Future<void> _pending = Future.value();

  /// Watches the stream of the parecord running as [capturePid].
  Future<void> start({
    required int capturePid,
    required void Function() onRouteLost,
  }) async {
    watch(capturePid: capturePid, onRouteLost: onRouteLost);

    final generation = _generation;
    final process = await Process.start(
      pactlBin,
      ['subscribe'],
      environment: {'LC_ALL': 'C'},
    );
    // A stop() while pactl starts ends this watch.
    if (generation != _generation) {
      process.kill();
      return;
    }

    _subscribe = process;
    process.stderr.drain<void>().ignore();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_enqueue, onError: (_) {});

    // The stream may have linked before the subscription started.
    _enqueue("Event 'new' on source-output #0");
  }

  /// Arms the monitor without subscribing; [handleEvent] then feeds it.
  @visibleForTesting
  void watch({required int capturePid, required void Function() onRouteLost}) {
    stop();

    _capturePid = capturePid;
    _onRouteLost = onRouteLost;
  }

  void stop() {
    _generation++;
    _onRouteLost = null;
    _capturePid = null;
    _source = null;
    _subscribe?.kill();
    _subscribe = null;
  }

  // Events run one at a time, in order: PulseAudio reports the rescue move
  // before the removal.
  void _enqueue(String line) {
    _pending = _pending.then((_) => handleEvent(line)).catchError((Object e) {
      debugPrint(e.toString());
    });
  }

  @visibleForTesting
  Future<void> handleEvent(String line) async {
    final event = parsePactlEvent(line);
    if (event == null || _onRouteLost == null) return;

    switch (event) {
      case (type: 'remove', facility: 'source', index: final index):
        if (index == _source) _routeLost();

      case (type: 'new' || 'change', facility: 'source-output', index: _):
        await _refreshSource();
    }
  }

  // Follows moves made by the user or the server, unless the move is a
  // rescue from a source that is gone.
  Future<void> _refreshSource() async {
    final pid = _capturePid;
    if (pid == null) return;

    // A watch restarted while pactl runs makes its answer stale.
    final generation = _generation;
    final current = parseStreamSource(
      await run(['list', 'source-outputs']),
      pid,
    );
    if (generation != _generation) return;
    if (current == null || current == _source) return;

    if (_source case final previous?) {
      final sources = parseShortIndexes(
        await run(['list', 'short', 'sources']),
      );
      if (generation != _generation) return;
      if (!sources.contains(previous)) return _routeLost();
    }

    _source = current;
  }

  void _routeLost() {
    final onRouteLost = _onRouteLost;
    // Reports once: the owner restarts the watch for the next capture.
    stop();
    onRouteLost?.call();
  }
}

/// Reads a `pactl subscribe` line, like `Event 'remove' on source #54`.
@visibleForTesting
({String type, String facility, int index})? parsePactlEvent(String line) {
  final match = RegExp(r"^Event '(\w+)' on ([\w-]+) #(\d+)$").firstMatch(line);
  if (match == null) return null;

  return (
    type: match.group(1)!,
    facility: match.group(2)!,
    index: int.parse(match.group(3)!),
  );
}

/// Finds the source index of the stream that process [pid] owns in
/// `pactl list source-outputs`.
@visibleForTesting
int? parseStreamSource(List<String> output, int pid) {
  int? source;
  int? owner;

  for (final line in output) {
    final trimmed = line.trim();

    if (line.startsWith('Source Output #')) {
      if (owner == pid) break;
      source = null;
      owner = null;
    } else if (trimmed.startsWith('Source:')) {
      source = int.tryParse(trimmed.substring('Source:'.length).trim());
    } else if (trimmed.startsWith('application.process.id')) {
      final value = trimmed.substring(trimmed.indexOf('=') + 1).trim();
      owner = int.tryParse(value.replaceAll('"', ''));
    }
  }

  if (owner != pid) return null;
  // PipeWire lists an unlinked stream on PA_INVALID_INDEX.
  return source == 0xFFFFFFFF ? null : source;
}

/// Reads the first column of a `pactl list short` output.
@visibleForTesting
Set<int> parseShortIndexes(List<String> output) {
  return {for (final line in output) ?int.tryParse(line.split('\t').first)};
}
