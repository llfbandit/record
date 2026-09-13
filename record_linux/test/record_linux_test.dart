import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/record_linux.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// `RecordLinux` runs `parecord` and `ffmpeg` as child processes. These tests
/// swap both for shell scripts so the process plumbing is exercised without a
/// microphone or an encoder.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('record_linux_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<String> writeScript(String name, String body) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString('#!/bin/sh\n$body');
    await Process.run('chmod', ['+x', file.path]);
    return file.path;
  }

  test(
    'stop completes when ffmpeg floods stderr before reading stdin',
    () async {
      // A capture source that emits 3.2 MB of silence, then holds the process
      // open the way a live microphone does until it is killed.
      final parecord = await writeScript(
        'parecord',
        'dd if=/dev/zero bs=3200 count=1000 2>/dev/null\nexec sleep 1000\n',
      );
      // An encoder that writes more than any pipe buffer holds to stderr
      // before it consumes a single byte of input. The real ffmpeg does the
      // same, only slower: one progress line every half second until the
      // pipe is full, and then it blocks forever if nobody reads it.
      final ffmpeg = await writeScript(
        'ffmpeg',
        'for a; do out="\$a"; done\n'
            'head -c 1048576 /dev/zero >&2\n'
            'cat > "\$out"\n',
      );
      final output = '${tempDir.path}/take.m4a';

      final recorder = RecordLinux(parecordBin: parecord, ffmpegBin: ffmpeg);
      await recorder.start('r', const RecordConfig(), path: output);
      // Give the fake parecord time to emit its input.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final stopped = await recorder
          .stop('r')
          .timeout(const Duration(seconds: 10));

      expect(stopped, output);
      expect(File(output).lengthSync(), 3200 * 1000);
    },
  );
}
