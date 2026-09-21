@TestOn('linux')
library;

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

  // A hung stop() leaves the fakes alive; the test timeout won't kill them.
  tearDown(() async {
    for (final entry in tempDir.listSync().whereType<File>()) {
      if (!entry.path.endsWith('.pid')) continue;
      final pid = int.tryParse(entry.readAsStringSync().trim());
      if (pid != null) Process.killPid(pid, ProcessSignal.sigkill);
    }

    await tempDir.delete(recursive: true);
  });

  // Scripts write their pid for teardown; `exec` keeps it valid.
  Future<String> writeScript(String name, String body) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(
      '#!/bin/sh\necho \$\$ > "${file.path}.pid"\n$body',
    );
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
            'head -c 2097152 /dev/zero >&2\n'
            'cat > "\$out"\n',
      );
      final output = '${tempDir.path}/take.m4a';

      final recorder = RecordLinux.withExecutables(
        parecordBin: parecord,
        ffmpegBin: ffmpeg,
      );
      await recorder.start('r', const RecordConfig(), path: output);

      // Best effort: let most input reach the encoder before stop().
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        if (File(output).existsSync() &&
            File(output).lengthSync() >= 3200 * 1000) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // Without the drain, ffmpeg blocks on stderr and never returns.
      final stopped = await recorder
          .stop('r')
          .timeout(const Duration(seconds: 10));

      expect(stopped, output);
      expect(
        File(output).lengthSync(),
        3200 * 1000,
        reason: 'every captured byte should reach the encoder',
      );
    },
  );
}
