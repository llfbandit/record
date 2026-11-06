@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
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

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Waits until the fake says it is ready, and fails if it never does.
  ///
  /// Process.start() returning only means the program was launched: its trap
  /// is in place when it says so itself.
  Future<void> waitForReady(String script) async {
    final marker = File('$script.ready');
    await waitFor(marker.existsSync);

    expect(marker.existsSync(), isTrue, reason: 'the fake should be ready');
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

  test('a parecord that exits on its own is reported', () async {
    final parecord = await writeScript('parecord', 'exit 3\n');
    final exits = <String>[];

    final pipeline = CapturePipeline(parecordBin: parecord)
      ..onExited = (error, {required capture}) {
        if (capture) exits.add(error);
      };
    await pipeline.startStream(const RecordConfig());
    await waitFor(() => exits.isNotEmpty);
    await pipeline.stop();

    expect(exits, ['parecord exited (3).']);
  });

  test('an ffmpeg that exits on its own is reported', () async {
    final parecord = await writeScript('parecord', 'exec sleep 1000\n');
    final ffmpeg = await writeScript('ffmpeg', 'exit 1\n');
    final exits = <String>[];

    final pipeline = CapturePipeline(parecordBin: parecord, ffmpegBin: ffmpeg)
      ..onExited = (error, {required capture}) {
        if (!capture) exits.add(error);
      };
    await pipeline.startFile(const RecordConfig(), '${tempDir.path}/take.wav');
    await waitFor(() => exits.isNotEmpty);
    await pipeline.stop().timeout(const Duration(seconds: 10));

    expect(exits, ['ffmpeg exited (1).']);
  });

  test('ffmpeg logs only errors', () async {
    final parecord = await writeScript('parecord', 'exec sleep 1000\n');
    final ffmpeg = await writeScript(
      'ffmpeg',
      'echo "\$@" > "${tempDir.path}/args"\nexec cat > /dev/null\n',
    );

    final pipeline = CapturePipeline(parecordBin: parecord, ffmpegBin: ffmpeg);
    await pipeline.startFile(const RecordConfig(), '${tempDir.path}/take.wav');
    await waitFor(() => File('${tempDir.path}/args').existsSync());
    await pipeline.stop().timeout(const Duration(seconds: 10));

    expect(
      File('${tempDir.path}/args').readAsStringSync(),
      startsWith('-loglevel error -nostats '),
    );
  });

  test('an exit drops the line that trimming stderr cut', () async {
    final parecord = await writeScript(
      'parecord',
      'head -c 4096 /dev/zero | tr "\\0" x >&2\n'
          'printf "\\nStream error: No such entity\\n" >&2\n'
          'exit 1\n',
    );
    final exits = <String>[];

    final pipeline = CapturePipeline(parecordBin: parecord)
      ..onExited = (error, {required capture}) {
        if (capture) exits.add(error);
      };
    await pipeline.startStream(const RecordConfig());
    await waitFor(() => exits.isNotEmpty);
    await pipeline.stop();

    expect(exits, ['parecord exited (1): Stream error: No such entity']);
  });

  test('an exit reports the last lines of stderr', () async {
    final parecord = await writeScript(
      'parecord',
      'head -c 4096 /dev/zero | tr "\\0" x >&2\n'
          'printf "\\nline 1\\nline 2\\n\\nStream error: No such entity\\n" >&2\n'
          'exit 1\n',
    );
    final exits = <String>[];

    final pipeline = CapturePipeline(parecordBin: parecord)
      ..onExited = (error, {required capture}) {
        if (capture) exits.add(error);
      };
    await pipeline.startStream(const RecordConfig());
    await waitFor(() => exits.isNotEmpty);
    await pipeline.stop();

    expect(exits, [
      'parecord exited (1): line 1\nline 2\nStream error: No such entity',
    ]);
  });

  test('a capture the pipeline ends is not reported', () async {
    final parecord = await writeScript('parecord', 'exec sleep 1000\n');
    final ffmpeg = await writeScript('ffmpeg', 'exec cat > /dev/null\n');
    final exits = <String>[];

    final pipeline = CapturePipeline(parecordBin: parecord, ffmpegBin: ffmpeg)
      ..onExited = (error, {required capture}) => exits.add(error);
    await pipeline.startFile(const RecordConfig(), '${tempDir.path}/take.wav');
    await pipeline.restartCapture(const RecordConfig());
    await pipeline.stop().timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(exits, isEmpty);
  });

  test('stop ends a paused capture', () async {
    // Handles SIGTERM like parecord does: a stopped process holds a handled
    // signal until it continues, where a default one would kill it.
    final parecord = await writeScript(
      'parecord',
      "trap 'exit 0' TERM\n"
          'echo ready > "\$0.ready"\n'
          'while :; do sleep 0.1; done\n',
    );
    final ffmpeg = await writeScript('ffmpeg', 'exec cat > /dev/null\n');

    final pipeline = CapturePipeline(parecordBin: parecord, ffmpegBin: ffmpeg);
    await pipeline.startFile(const RecordConfig(), '${tempDir.path}/take.wav');
    final pid = pipeline.capturePid!;
    await waitForReady(parecord);

    pipeline.pause();
    await pipeline.stop().timeout(const Duration(seconds: 10));

    final proc = Directory('/proc/$pid');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (proc.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(proc.existsSync(), isFalse, reason: 'parecord should exit');
  });

  test('stop returns once the capture is gone', () async {
    // Handles SIGTERM like parecord does, and takes a moment over it, the way
    // a process that still flushes its buffers would.
    final parecord = await writeScript(
      'parecord',
      "trap 'sleep 0.3; exit 0' TERM\n"
          'echo ready > "\$0.ready"\n'
          'while :; do sleep 0.1; done\n',
    );

    final pipeline = CapturePipeline(parecordBin: parecord);
    final stream = await pipeline.startStream(const RecordConfig());
    stream.listen((_) {});
    final pid = pipeline.capturePid!;
    await waitForReady(parecord);

    await pipeline.stop().timeout(const Duration(seconds: 10));

    expect(
      Directory('/proc/$pid').existsSync(),
      isFalse,
      reason: 'stop must not return while the capture is still alive',
    );
  });

  test('a capture that ignores SIGTERM is killed', () async {
    // A source SIGTERM cannot end: without a kill it keeps the microphone for
    // as long as the app runs.
    final parecord = await writeScript(
      'parecord',
      "trap '' TERM\n"
          'echo ready > "\$0.ready"\n'
          'while :; do sleep 0.1; done\n',
    );

    final pipeline = CapturePipeline(
      parecordBin: parecord,
      stopTimeout: const Duration(milliseconds: 200),
    );
    final stream = await pipeline.startStream(const RecordConfig());
    stream.listen((_) {});
    final pid = pipeline.capturePid!;
    await waitForReady(parecord);

    await pipeline.stop().timeout(const Duration(seconds: 10));

    final proc = Directory('/proc/$pid');
    await waitFor(() => !proc.existsSync());

    expect(proc.existsSync(), isFalse, reason: 'SIGTERM alone does not end it');
  });

  /// What the log should look like, whichever timeout ran out.
  Matcher killLog(int pid, int ms, String after, String timeout) {
    return matches(
      RegExp(
        '^record_linux: parecord $pid did not end within $ms ms after '
        '${RegExp.escape(after)} \\(state \\S+, waiting in \\S+, '
        'SIGTERM (pending|not pending), (ignored|handled|default)\\), '
        'sending SIGKILL\\. Timeout: $timeout, to be configurable via '
        'RecordLinuxOptions, see '
        'https://github\\.com/llfbandit/record/issues/640\$',
      ),
    );
  }

  /// Collects what the pipeline logs while a test runs.
  List<String?> collectLogs() {
    final logged = <String?>[];
    final wasDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message);
    addTearDown(() => debugPrint = wasDebugPrint);

    return logged;
  }

  test('a kill after the stop timeout is logged', () async {
    final parecord = await writeScript(
      'parecord',
      "trap '' TERM\n"
          'echo ready > "\$0.ready"\n'
          'while :; do sleep 0.1; done\n',
    );
    final logged = collectLogs();

    final pipeline = CapturePipeline(
      parecordBin: parecord,
      stopTimeout: const Duration(milliseconds: 200),
    );
    final stream = await pipeline.startStream(const RecordConfig());
    stream.listen((_) {});
    final pid = pipeline.capturePid!;
    await waitForReady(parecord);

    await pipeline.stop().timeout(const Duration(seconds: 10));

    expect(logged.single, killLog(pid, 200, 'stop()', 'stopTimeout'));
  });

  test('a kill after the restart timeout is logged', () async {
    final parecord = await writeScript(
      'parecord',
      "trap '' TERM\n"
          'echo ready > "\$0.ready"\n'
          'while :; do sleep 0.1; done\n',
    );
    final logged = collectLogs();

    final pipeline = CapturePipeline(
      parecordBin: parecord,
      stopTimeout: const Duration(seconds: 30),
      restartStopTimeout: const Duration(milliseconds: 200),
    );
    final stream = await pipeline.startStream(const RecordConfig());
    stream.listen((_) {});
    final pid = pipeline.capturePid!;
    await waitForReady(parecord);

    await pipeline.stop(restarting: true).timeout(const Duration(seconds: 10));

    expect(
      logged.single,
      killLog(pid, 200, 'a new start()', 'restartStopTimeout'),
    );
  });

  test('a new take shortens the wait for a capture that hangs', () async {
    final parecord = await writeScript(
      'parecord',
      "trap '' TERM\n"
          'echo ready > "\$0.ready"\n'
          'while :; do sleep 0.1; done\n',
    );
    collectLogs();

    final pipeline = CapturePipeline(
      parecordBin: parecord,
      stopTimeout: const Duration(seconds: 30),
      restartStopTimeout: const Duration(milliseconds: 200),
    );
    final stream = await pipeline.startStream(const RecordConfig());
    stream.listen((_) {});
    final pid = pipeline.capturePid!;
    await waitForReady(parecord);

    final started = DateTime.now();
    final stopping = pipeline.stop();
    // 50 ms into a stop that would wait 30 s, a new take asks for the
    // capture to go.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    pipeline.hurryEnds();

    await stopping.timeout(const Duration(seconds: 5));
    final waited = DateTime.now().difference(started);

    expect(Directory('/proc/$pid').existsSync(), isFalse);
    expect(
      waited,
      lessThan(const Duration(seconds: 2)),
      reason: 'the kill follows the restart timeout, not the stop timeout',
    );
  });

  /// The pids of the processes that are running [script] right now.
  ///
  /// Read from the command lines, not from what a fake wrote: one that was
  /// killed before it could write anything still has to be found.
  Set<int> running(String script) {
    final pids = <int>{};

    for (final entry in Directory('/proc').listSync()) {
      final pid = int.tryParse(entry.path.split('/').last);
      if (pid == null) continue;

      try {
        if (File('${entry.path}/cmdline').readAsStringSync().contains(script)) {
          pids.add(pid);
        }
      } on FileSystemException {
        // The process ended while /proc was being read.
      }
    }

    return pids;
  }

  test('stop waits for a capture that was still starting', () async {
    // The first capture ends on SIGTERM and the second ignores it, so only a
    // stop that waits for the second one can tell that it is gone.
    final parecord = await writeScript(
      'parecord',
      'if [ -e "\$0.first" ]; then trap \'\' TERM; '
          'else : > "\$0.first"; trap \'exit 0\' TERM; fi\n'
          'echo ready > "\$0.ready"\n'
          'while :; do sleep 0.1; done\n',
    );

    final pipeline = CapturePipeline(
      parecordBin: parecord,
      stopTimeout: const Duration(milliseconds: 300),
    );
    final stream = await pipeline.startStream(const RecordConfig());
    stream.listen((_) {});
    final first = pipeline.capturePid!;
    await waitForReady(parecord);

    // The route move is still inside Process.start() when the stop runs, so
    // the capture it brings up joins the ends after the stop looked at them.
    final moving = pipeline.restartCapture(const RecordConfig());
    final stopping = pipeline.stop();
    // The restart completing says Process.start() succeeded, so the second
    // capture did run; how far it got before the stop reached it is a race.
    await Future.wait([moving, stopping]).timeout(const Duration(seconds: 10));

    expect(
      running(parecord).where((pid) => pid != first),
      isEmpty,
      reason: 'stop must wait for a capture that was still starting',
    );
  });

  /// A fake that no SIGTERM can end, so only a kill closes it.
  Future<String> writeDeafFake() => writeScript(
    'parecord',
    "trap '' TERM\n"
        'echo ready > "\$0.ready"\n'
        'while :; do sleep 0.1; done\n',
  );

  test(
    'a new take holds a late capture to the deadline it asked for',
    () async {
      final parecord = await writeDeafFake();
      final logged = collectLogs();

      final pipeline = CapturePipeline(
        parecordBin: parecord,
        stopTimeout: const Duration(seconds: 3),
        restartStopTimeout: const Duration(milliseconds: 300),
      );
      final stream = await pipeline.startStream(const RecordConfig());
      stream.listen((_) {});
      final first = pipeline.capturePid!;
      await waitForReady(parecord);

      final started = DateTime.now();
      // The capture of the route move is still starting when the stop runs, and
      // a new take hurries that stop before it turns up.
      final moving = pipeline.restartCapture(const RecordConfig());
      final stopping = pipeline.stop();
      pipeline.hurryEnds();
      await Future.wait([
        moving,
        stopping,
      ]).timeout(const Duration(seconds: 10));
      final waited = DateTime.now().difference(started);

      expect(
        running(parecord).where((pid) => pid != first),
        isEmpty,
        reason: 'the late capture has to be gone as well',
      );
      expect(
        waited,
        lessThan(const Duration(milliseconds: 1500)),
        reason:
            'the late capture waits for the hurried deadline, not the long one',
      );
      expect(
        logged.where((line) => line!.contains('Timeout: stopTimeout')),
        isEmpty,
        reason: 'nothing may fall back on the stop timeout after a hurry',
      );
    },
  );

  test('a late capture past its deadline is killed at once', () async {
    final parecord = await writeDeafFake();
    final logged = collectLogs();

    // A deadline so short that it has passed by the time the capture of the
    // route move turns up.
    final pipeline = CapturePipeline(
      parecordBin: parecord,
      stopTimeout: const Duration(seconds: 3),
      restartStopTimeout: Duration.zero,
    );
    final stream = await pipeline.startStream(const RecordConfig());
    stream.listen((_) {});
    final first = pipeline.capturePid!;
    await waitForReady(parecord);

    final started = DateTime.now();
    final moving = pipeline.restartCapture(const RecordConfig());
    final stopping = pipeline.stop();
    pipeline.hurryEnds();
    await Future.wait([moving, stopping]).timeout(const Duration(seconds: 10));
    final waited = DateTime.now().difference(started);

    expect(
      running(parecord).where((pid) => pid != first),
      isEmpty,
      reason: 'a capture whose deadline has passed goes at once',
    );
    expect(waited, lessThan(const Duration(milliseconds: 1500)));
    expect(
      logged.where(
        (line) =>
            line!.contains('sending SIGKILL') &&
            !line.contains('parecord $first '),
      ),
      isNotEmpty,
      reason: 'the kill is logged even when it needs no timer',
    );
  });

  test('a capture that already exited is not killed again', () async {
    // It is gone before the take ends, so its exit code is known to Dart by
    // the time the stop reaches it.
    final parecord = await writeScript('parecord', 'exit 0\n');
    final logged = collectLogs();
    final exits = <String>[];

    // A deadline that is up the moment it is set.
    final pipeline = CapturePipeline(
      parecordBin: parecord,
      restartStopTimeout: Duration.zero,
    )..onExited = (error, {required capture}) => exits.add(error);
    final stream = await pipeline.startStream(const RecordConfig());
    stream.listen((_) {});
    final pid = pipeline.capturePid!;

    // The exit being reported means Dart has read the exit code.
    await waitFor(() => exits.isNotEmpty);
    expect(exits, isNotEmpty, reason: 'the capture should have exited');

    await pipeline.stop(restarting: true).timeout(const Duration(seconds: 10));

    expect(Directory('/proc/$pid').existsSync(), isFalse);
    expect(
      logged.where((line) => line!.contains('sending SIGKILL')),
      isEmpty,
      reason: 'a capture that is gone is neither killed nor read from /proc',
    );
  });

  group('comesSooner', () {
    const short = Duration(milliseconds: 100);
    const long = Duration(milliseconds: 300);

    test('takes the first deadline there is', () {
      expect(comesSooner(short, null), isTrue);
    });

    test('takes a deadline that is sooner', () {
      expect(comesSooner(short, long), isTrue);
    });

    // What a hurry must never do, however the wall clock behaves.
    test('keeps a deadline that is already sooner', () {
      expect(comesSooner(long, short), isFalse);
    });

    test('keeps the deadline it already has', () {
      expect(comesSooner(short, short), isFalse);
    });
  });
}
