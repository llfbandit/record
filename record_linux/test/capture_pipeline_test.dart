@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/capture_pipeline.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// `CapturePipeline` runs parecord and ffmpeg as child processes. These tests
/// swap both for shell scripts, so no microphone or encoder is needed.
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

      final pipeline = CapturePipeline(
        parecordBin: parecord,
        ffmpegBin: ffmpeg,
      );
      await pipeline.startFile(const RecordConfig(), output);

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
      await pipeline.stop().timeout(const Duration(seconds: 10));

      expect(
        File(output).lengthSync(),
        3200 * 1000,
        reason: 'every captured byte should reach the encoder',
      );
    },
  );

  Future<void> waitForLength(String path, int length) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (File(path).existsSync() && File(path).lengthSync() >= length) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('a restarted capture keeps writing to the same file', () async {
    final parecord = await writeScript(
      'parecord',
      'dd if=/dev/zero bs=3200 count=10 2>/dev/null\nexec sleep 1000\n',
    );
    final ffmpeg = await writeScript(
      'ffmpeg',
      'for a; do out="\$a"; done\ncat > "\$out"\n',
    );
    final output = '${tempDir.path}/take.wav';

    final pipeline = CapturePipeline(parecordBin: parecord, ffmpegBin: ffmpeg);
    await pipeline.startFile(const RecordConfig(), output);
    await waitForLength(output, 32000);

    await pipeline.restartCapture(const RecordConfig());
    await waitForLength(output, 64000);

    await pipeline.stop().timeout(const Duration(seconds: 10));

    expect(File(output).lengthSync(), 64000);
  });

  test('stop ends a paused capture', () async {
    // Handles SIGTERM like parecord does: a stopped process holds a handled
    // signal until it continues, where a default one would kill it.
    final parecord = await writeScript(
      'parecord',
      "trap 'exit 0' TERM\nwhile :; do sleep 0.1; done\n",
    );
    final ffmpeg = await writeScript('ffmpeg', 'exec cat > /dev/null\n');

    final pipeline = CapturePipeline(parecordBin: parecord, ffmpegBin: ffmpeg);
    await pipeline.startFile(const RecordConfig(), '${tempDir.path}/take.wav');
    final pid = pipeline.capturePid!;

    pipeline.pause();
    await pipeline.stop().timeout(const Duration(seconds: 10));

    final proc = Directory('/proc/$pid');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (proc.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(proc.existsSync(), isFalse, reason: 'parecord should exit');
  });
}
