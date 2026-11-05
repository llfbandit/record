import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/output_tail.dart';

void main() {
  /// Feeds [chunks] to a tail and closes the pipe.
  Future<String> tailOf(List<String> chunks) async {
    final output = StreamController<List<int>>();
    final tail = OutputTail(output.stream);
    for (final chunk in chunks) {
      output.add(utf8.encode(chunk));
    }
    await output.close();
    return tail.text();
  }

  test('keeps the last three lines', () async {
    expect(await tailOf(['a\nb\n', '\nc\n', 'd\n']), 'b\nc\nd');
  });

  test('is empty without output', () async {
    expect(await tailOf([]), '');
  });

  test('drops the line that trimming cut', () async {
    expect(await tailOf(['${'x' * 2000}\nerror\n']), 'error');
  });

  test('drops the cut line when a full chunk replaces the buffer', () async {
    // Exactly 1024 bytes, continuing the line 'before' started.
    final chunk = '${'x' * (1024 - 7)}\nerror\n';

    expect(await tailOf(['before', chunk]), 'error');
  });

  test('keeps a line that starts the window', () async {
    const last = '\nStream error: No such entity\nend\n';
    // The kept 1024 bytes start right after the newline after 'noise'.
    final line = 'z' * (1024 - last.length);

    expect(
      await tailOf(['noise\n$line', last]),
      '$line\nStream error: No such entity\nend',
    );
  });

  test('keeps a fragment of one long line', () async {
    expect(await tailOf(['y' * 2000]), 'y' * 1024);
  });

  test('keeps a fragment followed only by blank lines', () async {
    expect(await tailOf(['y' * 2000, '\n \n']), 'y' * 1021);
  });

  test('stops waiting for a pipe that stays open', () async {
    final output = StreamController<List<int>>();
    final tail = OutputTail(
      output.stream,
      closeWait: const Duration(milliseconds: 10),
    );
    output.add(utf8.encode('error\n'));

    expect(await tail.text(), 'error');
    await output.close();
  });
}
