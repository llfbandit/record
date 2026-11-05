import 'dart:async';
import 'dart:convert';

/// Drains a process output pipe, keeping its end to tell why the process exited.
class OutputTail {
  OutputTail(
    Stream<List<int>> output, {
    this.closeWait = const Duration(milliseconds: 500),
  }) {
    output.listen(
      _add,
      onError: (_) => _complete(),
      onDone: _complete,
      cancelOnError: true,
    );
  }

  /// How long [text] waits for the pipe to close, as a child process may
  /// still hold it open.
  final Duration closeWait;

  // Bounded: a process may log for the whole take.
  static const _maxBytes = 1024;
  static const _maxLines = 3;

  final _done = Completer<void>();
  var _bytes = <int>[];
  // Trimming started the kept bytes mid-line.
  var _cut = false;

  /// The last lines, once the pipe closes or [closeWait] runs out.
  Future<String> text() async {
    await _done.future.timeout(closeWait, onTimeout: () {});

    final lines = const LineSplitter().convert(
      utf8.decode(_bytes, allowMalformed: true),
    );
    // Drop the cut line, maybe split mid-character, unless nothing else is left.
    if (_cut && lines.skip(1).any((line) => line.trim().isNotEmpty)) {
      lines.removeAt(0);
    }

    final kept = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final first = kept.length > _maxLines ? kept.length - _maxLines : 0;
    return kept.sublist(first).join('\n');
  }

  void _add(List<int> chunk) {
    final bytes = [..._bytes, ...chunk];
    final drop = bytes.length - _maxBytes;
    if (drop <= 0) {
      _bytes = bytes;
      return;
    }

    // A window that starts right after a newline holds whole lines.
    _cut = bytes[drop - 1] != 0x0A;
    _bytes = bytes.sublist(drop);
  }

  void _complete() {
    if (!_done.isCompleted) _done.complete();
  }
}
