import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/capture_pipeline.dart';
import 'package:record_linux/src/linux_recorder.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// Runs no process: stop() waits until the test lets it end, and the calls it
/// gets are counted - the stops, the ones a new take makes, and the hurrying.
class _SlowStopPipeline extends CapturePipeline {
  Completer<void> stopping = Completer()..complete();
  final calls = <String>[];
  int stops = 0;
  int restarts = 0;
  int hurried = 0;

  @override
  Future<void> startFile(RecordConfig config, String path) async {}

  @override
  Future<void> stop({bool restarting = false}) {
    stops++;
    if (restarting) restarts++;
    return stopping.future;
  }

  @override
  void hurryEnds() => hurried++;

  @override
  void pause() => calls.add('pause');

  @override
  void resume() => calls.add('resume');
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

  // An app may pause or resume while a stop, or a route change that ends the
  // take, is still running.
  test('a pause or a resume while the take ends changes nothing', () async {
    final states = <RecordState>[];
    recorder.onStateChanged().listen(states.add);

    await recorder.start(const RecordConfig(), path: '/tmp/take.m4a');

    pipeline.stopping = Completer();
    final ending = recorder.stop();
    await recorder.pause();
    await recorder.resume();
    pipeline.stopping.complete();
    await ending;
    await pumpEventQueue();

    expect(states, [RecordState.record, RecordState.stop]);
    expect(pipeline.calls, isEmpty, reason: 'the capture must not be frozen');
    expect(recorder.isRecording(), isFalse);
    expect(recorder.isPaused(), isFalse);
  });

  test('a pause or a resume while the take ends is logged', () async {
    final logged = <String?>[];
    final wasDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message);
    addTearDown(() => debugPrint = wasDebugPrint);

    await recorder.start(const RecordConfig(), path: '/tmp/take.m4a');

    pipeline.stopping = Completer();
    final ending = recorder.stop();
    await recorder.pause();
    await recorder.resume();
    pipeline.stopping.complete();
    await ending;

    expect(logged, [
      'record_linux: pause() ignored: stop is already running',
      'record_linux: resume() ignored: stop is already running',
    ]);
  });

  test('a second stop joins the running one', () async {
    final logged = <String?>[];
    final wasDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message);
    addTearDown(() => debugPrint = wasDebugPrint);

    await recorder.start(const RecordConfig(), path: '/tmp/take.m4a');
    // start() ends any previous take: count only what follows.
    pipeline.stops = 0;

    pipeline.stopping = Completer();
    final first = recorder.stop();
    // The second caller gets the end that is running, not a future of its
    // own, so what counts is that it waits for it and reports its path.
    final second = recorder.stop();
    pipeline.stopping.complete();

    expect(await first, '/tmp/take.m4a');
    expect(await second, '/tmp/take.m4a');
    expect(pipeline.stops, 1, reason: 'one end, with both callers waiting');
    expect(logged, ['record_linux: stop() ignored: stop is already running']);
  });

  test('a new take ends the running one with the restart timeout', () async {
    await recorder.start(const RecordConfig(), path: '/tmp/take.m4a');
    // start() ends any previous take: count only what follows.
    pipeline.stops = 0;
    pipeline.restarts = 0;

    await recorder.start(const RecordConfig(), path: '/tmp/next.m4a');

    expect(pipeline.stops, 1);
    expect(pipeline.restarts, 1, reason: 'a new take waits the short time');
  });

  test('a new take joins an end that runs and hurries it', () async {
    final logged = <String?>[];
    final wasDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message);
    addTearDown(() => debugPrint = wasDebugPrint);

    await recorder.start(const RecordConfig(), path: '/tmp/take.m4a');
    // start() ends any previous take: count only what follows.
    pipeline.stops = 0;

    pipeline.stopping = Completer();
    final ending = recorder.stop();
    final starting = recorder.start(
      const RecordConfig(),
      path: '/tmp/next.m4a',
    );
    pipeline.stopping.complete();
    await ending;
    await starting;

    expect(pipeline.stops, 1, reason: 'the new take joins the end that runs');
    expect(pipeline.hurried, 1, reason: 'and does not wait out its timeout');
    expect(logged, ['record_linux: stop() ignored: stop is already running']);
  });
}
