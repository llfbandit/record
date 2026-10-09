@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/record_linux.dart';
import 'package:record_linux/src/capture_pipeline.dart';
import 'package:record_linux/src/linux_recorder.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// Swaps parecord for a script, so no microphone is needed.
void main() {
  late Directory tempDir;
  late RecordLinux platform;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('record_linux_test_');

    // A live source: one 3200-byte chunk every 50 ms until killed.
    final parecord = File('${tempDir.path}/parecord');
    await parecord.writeAsString(
      '#!/bin/sh\nwhile :; do head -c 3200 /dev/zero; sleep 0.05; done\n',
    );
    await Process.run('chmod', ['+x', parecord.path]);

    platform = RecordLinux(
      newRecorder: () =>
          LinuxRecorder(pipeline: CapturePipeline(parecordBin: parecord.path)),
    );
  });

  tearDown(() async {
    for (final id in ['a', 'b']) {
      try {
        await platform.dispose(id);
      } on PlatformException {
        // Already disposed by the test.
      }
    }
    await tempDir.delete(recursive: true);
  });

  test('disposing one recorder leaves another capturing', () async {
    await platform.create('a');
    final states = <RecordState>[];
    platform.onStateChanged('a').listen(states.add);

    var bytes = 0;
    final stream = await platform.startStream('a', const RecordConfig());
    stream.listen((data) => bytes += data.length);

    await platform.create('b');
    await platform.listInputDevices('b').catchError((_) => <InputDevice>[]);
    await platform.dispose('b');

    final before = bytes;
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(bytes, greaterThan(before), reason: 'A should keep capturing');
    expect(await platform.isRecording('a'), isTrue);
    expect(states, [RecordState.record], reason: 'B must not stop A');
  });

  test('starting one recorder leaves another capturing', () async {
    await platform.create('a');
    await platform.create('b');

    var bytes = 0;
    final stream = await platform.startStream('a', const RecordConfig());
    stream.listen((data) => bytes += data.length);

    final other = await platform.startStream('b', const RecordConfig());
    other.listen((_) {});

    final before = bytes;
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(bytes, greaterThan(before));
    expect(await platform.isRecording('a'), isTrue);
    expect(await platform.isRecording('b'), isTrue);
  });

  test('throws for an unknown recorder', () {
    expect(
      () => platform.isRecording('nope'),
      throwsA(isA<PlatformException>()),
    );
  });
}
