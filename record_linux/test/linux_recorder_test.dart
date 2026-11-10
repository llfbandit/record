import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/capture_pipeline.dart';
import 'package:record_linux/src/linux_recorder.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// Runs no process: stop() waits until the test lets it end.
class _SlowStopPipeline extends CapturePipeline {
  Completer<void> stopping = Completer()..complete();
  // Runs inside startFile(), e.g. to fail it.
  void Function() starting = () {};
  int stops = 0;

  @override
  Future<void> startFile(RecordConfig config, String path) async => starting();

  @override
  Future<void> stop() {
    stops++;
    return stopping.future;
  }
}

void main() {
  late _SlowStopPipeline pipeline;
  late LinuxRecorder recorder;
  late Future<Set<String>> Function() listSources;

  setUp(() {
    pipeline = _SlowStopPipeline();
    listSources = () async => {'mic'};
    recorder = LinuxRecorder(
      pipeline: pipeline,
      listSources: () => listSources(),
    );
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
      Future<Set<String>> Function() sourcesAfter,
    ) async {
      final stops = <RecordStop>[];
      recorder.onStopped().listen(stops.add);

      await recorder.start(const RecordConfig(), path: '/tmp/take.m4a');
      listSources = sourcesAfter;
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

  group('start() throws', () {
    Future<void> expectStartThrows(Matcher matcher) async {
      final states = <RecordState>[];
      recorder.onStateChanged().listen(states.add);

      await expectLater(
        recorder.start(const RecordConfig(), path: '/tmp/take.m4a'),
        throwsA(matcher),
      );

      expect(states, isEmpty);
      expect(recorder.isRecording(), isFalse);
    }

    test('when the device is missing', () async {
      listSources = () async => {};

      await expectStartThrows(isA<PlatformException>());
      // Only start()'s own stop(): the pipeline never ran.
      expect(pipeline.stops, 1);
    });

    test('when capture exits while starting, and stops the pipeline', () async {
      pipeline.starting = () =>
          pipeline.onExited!('parecord exited (1).', capture: true);

      await expectStartThrows(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          'parecord exited (1).',
        ),
      );
      expect(pipeline.stops, 2);
    });

    // E.g. ffmpeg is missing while parecord already captures.
    test('when the pipeline fails, and stops it', () async {
      pipeline.starting = () =>
          throw const ProcessException('ffmpeg', [], 'not found', 2);

      await expectStartThrows(isA<ProcessException>());
      expect(pipeline.stops, 2);
    });
  });
}
