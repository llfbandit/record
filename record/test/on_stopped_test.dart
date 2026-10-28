import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'helpers/fake_record_platform.dart';
import 'helpers/test_utils.dart';

void main() {
  late FakeRecordPlatform fake;
  late AudioRecorder recorder;

  setUp(() async {
    fake = FakeRecordPlatform();
    RecordPlatform.instance = fake;
    recorder = AudioRecorder();
    await pump();
  });

  tearDown(() async {
    try {
      await recorder.dispose();
    } catch (_) {}
  });

  group('onStopped', () {
    test('receives the end of a take', () async {
      final stops = <RecordStop>[];
      recorder.onStopped().listen(stops.add);
      await pump();

      const stop = RecordStop(
        reason: RecordStopReason.routeChange,
        path: '/x.m4a',
      );
      fake.emitStop(stop);
      await pump();

      expect(stops, [stop]);
    });

    test('comes after RecordState.stop', () async {
      final events = <Object>[];
      recorder.onStopped().listen(events.add);
      recorder.onStateChanged().listen(events.add);
      await pump();

      const stop = RecordStop(reason: RecordStopReason.stop);
      fake.emitStop(stop);
      await pump();

      expect(events, [RecordState.stop, stop]);
    });

    test('is listened from start(), before the app listens', () async {
      await recorder.start(const RecordConfig(), path: '/x.m4a');
      expect(fake.calls, contains('onStopped'));
    });

    test('ignores errors: the state stream reports them', () async {
      final stops = <RecordStop>[];
      recorder.onStopped().listen(stops.add);
      recorder.onStateChanged().listen(null, onError: (_) {});
      await pump();

      fake.emitError(Exception('boom'));
      await pump();

      expect(stops, isEmpty);
    });

    test('receives the stop of the take dispose() ends', () async {
      final stops = <RecordStop>[];
      recorder.onStopped().listen(stops.add);
      await pump();

      const stop = RecordStop(reason: RecordStopReason.stop, path: '/x.m4a');
      fake.stopOnDispose = stop;
      await recorder.dispose();
      await pump();

      expect(stops, [stop]);
    });

    test('is a closed stream after dispose()', () async {
      await recorder.start(const RecordConfig(), path: '/x.m4a');
      await recorder.dispose();

      final done = Completer<void>();
      recorder.onStopped().listen(null, onDone: done.complete);
      await pump();

      expect(done.isCompleted, isTrue);
    });
  });
}
