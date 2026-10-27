import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/capture_pipeline.dart';
import 'package:record_linux/src/linux_recorder.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// Runs no process: stop() waits until the test lets it end.
class _SlowStopPipeline extends CapturePipeline {
  Completer<void> stopping = Completer()..complete();

  @override
  Future<void> startFile(RecordConfig config, String path) async {}

  @override
  Future<void> stop() => stopping.future;
}

void main() {
  late _SlowStopPipeline pipeline;
  late LinuxRecorder recorder;

  setUp(() {
    pipeline = _SlowStopPipeline();
    recorder = LinuxRecorder(pipeline: pipeline);
  });

  tearDown(() => recorder.dispose());

  // E.g. a route change stops the take while the app calls stop().
  test('two ends at once report one stop', () async {
    final states = <RecordState>[];
    final stops = <RecordStop>[];
    recorder.onStateChanged().listen(states.add);
    recorder.onStopped().listen(stops.add);

    await recorder.start(const RecordConfig(), path: '/tmp/take.m4a');

    pipeline.stopping = Completer();
    final first = recorder.stop();
    final second = recorder.stop();
    pipeline.stopping.complete();
    await Future.wait([first, second]);
    await pumpEventQueue();

    expect(states, [RecordState.record, RecordState.stop]);
    expect(stops, [
      const RecordStop(reason: RecordStopReason.stop, path: '/tmp/take.m4a'),
    ]);
  });

  test('an encoder that exits on its own ends the take', () async {
    final states = <RecordState>[];
    final stops = <RecordStop>[];
    recorder.onStateChanged().listen(states.add);
    recorder.onStopped().listen(stops.add);

    await recorder.start(const RecordConfig(), path: '/tmp/take.m4a');
    pipeline.onExited!('ffmpeg exited (1).', capture: false);
    await pumpEventQueue();

    expect(states, [RecordState.record, RecordState.stop]);
    expect(stops, [
      const RecordStop(
        reason: RecordStopReason.error,
        path: '/tmp/take.m4a',
        error: 'ffmpeg exited (1).',
      ),
    ]);
    expect(recorder.isRecording(), isFalse);
  });

  group('a capture that exits on its own', () {
    Future<List<RecordStop>> exitCapture(
      Future<Set<String>> Function() listSources,
    ) async {
      recorder = LinuxRecorder(pipeline: pipeline, listSources: listSources);
      final stops = <RecordStop>[];
      recorder.onStopped().listen(stops.add);

      await recorder.start(const RecordConfig(), path: '/tmp/take.m4a');
      pipeline.onExited!('parecord exited (1).', capture: true);
      await pumpEventQueue();

      return stops;
    }

    test('is left to the route monitor when its source is gone', () async {
      final stops = await exitCapture(() async => {});

      expect(stops, isEmpty);
      expect(recorder.isRecording(), isTrue);
    });

    // E.g. the sound server restarts: pactl fails along with parecord.
    test('ends the take when pactl fails', () async {
      final stops = await exitCapture(
        () async => throw const ProcessException('pactl', [], 'exited (1)', 1),
      );

      expect(stops, [
        const RecordStop(
          reason: RecordStopReason.error,
          path: '/tmp/take.m4a',
          error: 'parecord exited (1).',
        ),
      ]);
    });
  });
}
