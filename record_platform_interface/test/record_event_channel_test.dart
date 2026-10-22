import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recorderId = 'r1';
  const channel = EventChannel('com.llfbandit.record/events/$recorderId');
  late _Events events;
  late RecordPlatform platform;
  final subs = <StreamSubscription<Object>>[];

  setUp(() {
    events = _Events();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(channel, events);
    platform = RecordPlatform.instance;
  });

  // The streams live until their last listener goes.
  tearDown(() async {
    for (final sub in subs) {
      await sub.cancel();
    }
    subs.clear();
  });

  test('a stop comes as a state, then as its reason and file', () async {
    final states = <RecordState>[];
    final stops = <RecordStop>[];
    subs.add(platform.onStateChanged(recorderId).listen(states.add));
    subs.add(platform.onStopped(recorderId).listen(stops.add));
    await pumpEventQueue();

    events.send(RecordState.record.index);
    events.send({
      'state': RecordState.stop.index,
      'reason': 'routeChange',
      'path': '/x.m4a',
    });
    await pumpEventQueue();

    expect(states, [RecordState.record, RecordState.stop]);
    expect(stops, [
      const RecordStop(reason: RecordStopReason.routeChange, path: '/x.m4a'),
    ]);
  });

  test('an error has its message', () async {
    final stops = <RecordStop>[];
    subs.add(platform.onStopped(recorderId).listen(stops.add));
    await pumpEventQueue();

    events.send({
      'state': RecordState.stop.index,
      'reason': 'error',
      'error': 'Encoder failed.',
    });
    await pumpEventQueue();

    expect(stops, [
      const RecordStop(reason: RecordStopReason.error, error: 'Encoder failed.'),
    ]);
  });

  test('both streams share one listen on the platform side', () async {
    final a = platform.onStateChanged(recorderId).listen(null);
    final b = platform.onStopped(recorderId).listen(null);
    await pumpEventQueue();
    expect(events.listens, 1);

    await a.cancel();
    await b.cancel();
    await pumpEventQueue();
    expect(events.cancels, 1);

    // A new listen after the last one left opens the channel again.
    subs.add(platform.onStateChanged(recorderId).listen(null));
    await pumpEventQueue();
    expect(events.listens, 2);
  });
}

class _Events extends MockStreamHandler {
  MockStreamHandlerEventSink? _sink;
  int listens = 0;
  int cancels = 0;

  void send(Object? event) => _sink!.success(event);

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {
    listens++;
    _sink = events;
  }

  @override
  void onCancel(Object? arguments) => cancels++;
}
