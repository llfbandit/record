import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'platform/live_test_platform.dart';

// A guided test on a real device. The screen tells the user what to do,
// and the test checks what the recorder does.
class LiveTest {
  const LiveTest({
    required this.id,
    required this.title,
    required this.purpose,
    required this.needs,
    required this.config,
    required this.steps,
    this.stream = false,
    this.input = PickedInput.unused,
  });

  final String id;
  final String title;
  final String purpose;

  // What the user needs before starting.
  final String needs;

  final RecordConfig config;
  final Future<void> Function(LiveRun run) steps;

  // Records to a stream, else to a file.
  final bool stream;

  final PickedInput input;

  RecordConfig configWith(InputDevice? device) => input == PickedInput.recorded
      ? config.copyWith(device: (value: device))
      : config;

  String recap(InputDevice? device) {
    final c = configWith(device);
    final channels = c.numChannels == 1 ? 'mono' : '${c.numChannels} ch';
    return '${stream ? 'stream' : 'file'} · ${c.encoder.name} '
        '${c.sampleRate / 1000} kHz $channels · '
        'input: ${c.device?.label ?? 'default'} · '
        'route change: ${c.audioRouteChange.name} · '
        'interruption: ${c.audioInterruption.name}';
  }
}

// What a test does with the input picked on the screen.
enum PickedInput {
  unused,
  // The user connects it during the take. The take records from the default input.
  watched,
  // The take records from it.
  recorded,
}

class Check {
  const Check(this.name, this.ok, this.actual, [this.expected]);

  final String name;
  final bool ok;
  final String actual;
  final String? expected;

  @override
  String toString() =>
      '${ok ? '✓' : '✗'} $name: $actual'
      '${expected == null ? '' : ' (expected $expected)'}';
}

enum Outcome { running, passed, failed, cancelled }

// A test step failed. The message says why.
class LiveTestFailure implements Exception {
  const LiveTestFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class _Cancelled implements Exception {}

// One run of a test. The screen listens to it.
class LiveRun extends ChangeNotifier {
  LiveRun(this.test, this.device);

  final LiveTest test;

  // The input picked on the screen, as last listed: Android gives it a new id when it comes back.
  InputDevice? device;

  final recorder = AudioRecorder();
  final _clock = Stopwatch();

  // What the recorder reported, with the time since the run began.
  final states = <(RecordState, Duration)>[];
  final configs = <(RecordConfig, Duration)>[];
  final errors = <Object>[];

  // Bytes received from the stream.
  int bytes = 0;
  String? path;

  final checks = <Check>[];
  final log = <String>[];
  Outcome outcome = Outcome.running;
  String? failure;

  // What the user must do now.
  String? instruction;

  // What the test waits for, and until when.
  String? waitingFor;
  Duration? waitEnds;

  // The user must tell when they are done: the app cannot see it.
  bool asksDone = false;

  Completer<void>? _done;
  Completer<void>? _streamEnded;
  bool _cancelled = false;
  final _subs = <StreamSubscription<Object?>>[];

  Duration get elapsed => _clock.elapsed;
  RecordState? get state => states.lastOrNull?.$1;
  RecordConfig get config => test.configWith(device);

  Future<void> run() async {
    _clock.start();
    say('Starting…');
    try {
      if (!await recorder.hasPermission()) {
        throw const LiveTestFailure('No permission to record.');
      }
      await test.steps(this);
      if (checks.any((c) => !c.ok)) {
        outcome = Outcome.failed;
        failure = 'Some checks failed.';
      } else {
        outcome = Outcome.passed;
      }
    } on _Cancelled {
      outcome = Outcome.cancelled;
    } catch (e) {
      outcome = Outcome.failed;
      failure = '$e';
      note('failed: $e');
    } finally {
      _clock.stop();
      instruction = null;
      waitingFor = null;
      asksDone = false;
      for (final s in _subs) {
        await s.cancel();
      }
      await recorder.dispose();
      notifyListeners();
      debugPrint(report.split('\n').map((l) => 'LIVETEST: $l').join('\n'));
    }
  }

  void cancel() {
    _cancelled = true;
    _done?.complete();
    _done = null;
  }

  void userDone() {
    _done?.complete();
    _done = null;
  }

  // MARK: - Steps

  void say(String text) {
    instruction = text;
    note('>>> $text');
  }

  void note(String text) {
    final s = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    log.add('$s s  $text');
    notifyListeners();
  }

  Future<void> start() async {
    _subs.add(
      recorder.onStateChanged().listen(
        (s) {
          states.add((s, elapsed));
          note('state: ${s.name}');
        },
        onError: (Object e) {
          errors.add(e);
          note('error: $e');
        },
      ),
    );
    await recorder.setOnConfigChanged((c) {
      configs.add((c, elapsed));
      note(
        'config changed: input ${c.device?.label ?? 'default'}, '
        '${c.sampleRate} Hz, ${c.numChannels} ch',
      );
    });

    if (test.stream) {
      final stream = await recorder.startStream(config);
      final ended = _streamEnded = Completer<void>();
      _subs.add(
        stream.listen(
          (chunk) {
            bytes += chunk.length;
            notifyListeners();
          },
          onError: (Object e) {
            errors.add(e);
            note('stream error: $e');
          },
          onDone: ended.complete,
        ),
      );
    } else {
      path = await tempPath('live_${test.id}');
      await recorder.start(config, path: path!);
    }
    note('started: ${test.recap(device)}');
    if (config.device != null) note('input id asked: ${config.device!.id}');
  }

  Future<void> pause() async {
    note('app calls pause()');
    await recorder.pause();
  }

  Future<void> resume() async {
    note('app calls resume()');
    final t0 = elapsed;
    await recorder.resume();
    note('resume() returned in ${(elapsed - t0).inMilliseconds} ms');
  }

  // The take must still record when the app stops it: else it ended by itself.
  Future<String?> stop({bool stillRecording = true}) async {
    if (stillRecording) {
      expectState(RecordState.record, 'still recording at stop()');
    }
    note('app calls stop()');
    final result = await recorder.stop();
    note('stop() returned $result');
    // The last chunks may come after stop() returns.
    await _streamEnded?.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => note('the stream did not end'),
    );
    return result;
  }

  Future<void> wait(double seconds, [String? why]) async {
    if (why != null) note(why);
    final end = elapsed + Duration(milliseconds: (seconds * 1000).round());
    while (elapsed < end) {
      _checkCancel();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  // Waits until cond is true, or fails the test after timeout.
  Future<void> waitFor(
    String what,
    FutureOr<bool> Function() cond, {
    double timeout = 60,
  }) async {
    waitingFor = what;
    waitEnds = elapsed + Duration(milliseconds: (timeout * 1000).round());
    final t0 = elapsed;
    try {
      while (elapsed < waitEnds!) {
        _checkCancel();
        if (await cond()) {
          note('ok: $what (${_seconds(elapsed - t0)} s)');
          return;
        }
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw LiveTestFailure('Timeout after ${timeout.round()} s: $what.');
    } finally {
      waitingFor = null;
      waitEnds = null;
    }
  }

  // For what the app cannot see: the user taps Done.
  Future<void> askDone(String text) async {
    say(text);
    asksDone = true;
    final done = _done = Completer<void>();
    notifyListeners();
    await done.future;
    asksDone = false;
    _checkCancel();
    note('user: done');
  }

  // MARK: - The chosen input

  // By its label too: Android gives a device a new id when it comes back.
  Future<bool> listed() async {
    final devices = await recorder.listInputDevices();
    final found = devices
        .where((d) => d.id == device!.id || d.label == device!.label)
        .firstOrNull;
    if (found != null && found.id != _listedId) {
      _listedId = found.id;
      note('"${found.label}" listed with id ${found.id}');
    }
    if (found != null) device = found;
    return found != null;
  }

  String? _listedId;

  Future<void> connected() async {
    if (await listed()) return;
    say('Connect "${device!.label}".');
    await waitFor('"${device!.label}" connected', listed, timeout: 120);
  }

  Future<void> disconnected() async {
    if (!await listed()) return;
    say('Disconnect "${device!.label}" before the test starts.');
    await waitFor('"${device!.label}" disconnected', () async {
      return !await listed();
    }, timeout: 120);
  }

  // A call goes to a Bluetooth headset. Removing it later is a route change, not the call.
  Future<void> noBluetooth() async {
    Future<List<InputDevice>> headsets() async =>
        (await recorder.listInputDevices())
            .where((d) => _bluetooth.contains(d.type))
            .toList();

    final found = await headsets();
    if (found.isEmpty) return;
    say(
      'Disconnect ${found.map((d) => '"${d.label}"').join(', ')} before the test starts.',
    );
    await waitFor(
      'no Bluetooth headset',
      () async => (await headsets()).isEmpty,
      timeout: 120,
    );
  }

  static const _bluetooth = {
    InputDeviceType.bluetoothSco,
    InputDeviceType.bluetoothA2dp,
    InputDeviceType.bluetoothLe,
  };

  // The user removes the input during the take.
  Future<void> removeInput() async {
    say(
      'Disconnect "${device!.label}" now: '
      'put the buds in their case, or unplug it.',
    );
    // The recorder may react before the list changes.
    await waitFor('"${device!.label}" disconnected', () async {
      return state != RecordState.record || !await listed();
    }, timeout: 120);
  }

  // MARK: - Checks

  void check(String name, bool ok, String actual, [String? expected]) {
    checks.add(Check(name, ok, actual, expected));
    notifyListeners();
  }

  void expectStates(List<RecordState> expected) {
    final actual = states.map((s) => s.$1).toList();
    check(
      'states',
      listEquals(actual, expected),
      _names(actual),
      _names(expected),
    );
  }

  void expectNoErrors() {
    check('no errors', errors.isEmpty, errors.isEmpty ? 'none' : '$errors');
  }

  // The reports that the take left the chosen input.
  Iterable<RecordConfig> movesSince(int mark) =>
      configs.skip(mark).map((c) => c.$1).where((c) => c.device == null);

  void expectMoves(int mark, int count) {
    final n = movesSince(mark).length;
    check(
      'moves reported (onConfigChanged, input: default)',
      n == count,
      '$n',
      '$count',
    );
  }

  void expectNoReports(int mark) {
    final n = configs.length - mark;
    check('config changes reported', n == 0, '$n', '0');
  }

  void expectState(RecordState expected, [String name = 'state']) {
    check(name, state == expected, '${state?.name}', expected.name);
  }

  // Seconds of audio in these bytes of the stream.
  double streamSeconds(int count) {
    final c = configs.lastOrNull?.$1 ?? config;
    // pcm16bits: 2 bytes per sample.
    return count / (2 * c.numChannels * c.sampleRate);
  }

  // Seconds spent in the record state.
  double get recordSeconds {
    var total = Duration.zero;
    Duration? since;
    for (final (s, at) in states) {
      if (s == RecordState.record) {
        since ??= at;
      } else if (since != null) {
        total += at - since;
        since = null;
      }
    }
    if (since != null) total += elapsed - since;
    return total.inMilliseconds / 1000;
  }

  // The audio kept must match the time spent recording.
  Future<void> expectAudio({double tolerance = 1.5}) async {
    final expected = recordSeconds;
    final actual = test.stream ? streamSeconds(bytes) : await wavSeconds(path!);
    if (actual == null) {
      note('audio length not measured here');
      return;
    }
    check(
      'audio kept',
      (actual - expected).abs() <= tolerance,
      '${actual.toStringAsFixed(1)} s',
      '≈ ${expected.toStringAsFixed(1)} ± $tolerance s',
    );
  }

  // Audio must come again after a mark in the stream.
  void expectAudioSince(int mark, double seconds, {double atLeast = 0.7}) {
    final got = streamSeconds(bytes - mark);
    check(
      'audio after that',
      got >= seconds * atLeast,
      '${got.toStringAsFixed(1)} s in ${seconds.toStringAsFixed(0)} s',
      '≥ ${(seconds * atLeast).toStringAsFixed(1)} s',
    );
  }

  // MARK: - Report

  String get report {
    final lines = [
      'record live test ${test.id}: ${test.title}',
      'platform: $osVersion${kIsWeb ? '' : ' (${defaultTargetPlatform.name})'}',
      'config: ${test.recap(device)}',
      'result: ${outcome.name.toUpperCase()}'
          '${failure == null ? '' : ' - $failure'}',
      if (checks.isNotEmpty) 'checks:',
      for (final c in checks) '  $c',
      'log:',
      for (final l in log) '  $l',
    ];
    return lines.join('\n');
  }

  // MARK: - Private

  void _checkCancel() {
    if (_cancelled) throw _Cancelled();
  }

  static String _names(List<RecordState> states) =>
      '[${states.map((s) => s.name).join(', ')}]';

  static String _seconds(Duration d) =>
      (d.inMilliseconds / 1000).toStringAsFixed(1);
}
