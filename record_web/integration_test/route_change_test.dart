import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/src/recorder/delegate/recorder_delegate.dart';
import 'package:web/web.dart' as web;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _TestDelegate delegate;
  late web.AudioContext context;

  setUp(() {
    delegate = _TestDelegate();
    context = web.AudioContext();
  });

  tearDown(() async {
    if (context.state != 'closed') {
      await context.close().toDart;
    }
  });

  // Gives a real stream with a live audio track, without asking for the mic.
  web.MediaStream createStream() {
    return context.createMediaStreamDestination().stream;
  }

  web.MediaStreamTrack firstTrack(web.MediaStream stream) {
    return stream.getAudioTracks().toDart.first;
  }

  // Lets a route-change handler run to its end.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('isSourceDead', () {
    testWidgets('is false while the track is live', (tester) async {
      expect(delegate.isSourceDead(createStream()), isFalse);
    });

    testWidgets('is true when all tracks are ended', (tester) async {
      final stream = createStream();

      for (final track in stream.getAudioTracks().toDart) {
        // stop() ends the track without firing the 'ended' event.
        track.stop();
      }

      expect(delegate.isSourceDead(stream), isTrue);
    });

    testWidgets('is true when the stream has no audio track', (tester) async {
      final stream = createStream();

      for (final track in stream.getAudioTracks().toDart) {
        stream.removeTrack(track);
      }

      expect(delegate.isSourceDead(stream), isTrue);
    });

    testWidgets('is true when there is no stream', (tester) async {
      expect(delegate.isSourceDead(null), isTrue);
    });
  });

  group('listenRouteChange', () {
    // Ends a track on its own and returns the calls the delegate made.
    Future<List<String>> endTrack(
      AudioRouteChangeMode mode, {
      Future<web.MediaStream> Function(RecordConfig config)? onReacquire,
    }) async {
      final stream = createStream();
      delegate = _TestDelegate(onReacquire: onReacquire)
        ..audioContext = context
        ..mediaStream = stream
        ..recordConfig = RecordConfig(audioRouteChange: mode);

      delegate.listenRouteChange(stream);
      firstTrack(stream).dispatchEvent(web.Event('ended'));
      await settle();

      return delegate.calls;
    }

    testWidgets('follow mode moves to the default device', (tester) async {
      final newStream = createStream();

      final calls = await endTrack(
        AudioRouteChangeMode.follow,
        onReacquire: (_) async => newStream,
      );

      expect(calls, ['swapped']);
      expect(delegate.mediaStream, same(newStream));
    });

    testWidgets('follow mode pauses when no device opens', (tester) async {
      final calls = await endTrack(
        AudioRouteChangeMode.follow,
        onReacquire: (_) async => throw StateError('no device'),
      );

      expect(calls, ['pause']);
    });

    testWidgets('pause mode pauses', (tester) async {
      expect(await endTrack(AudioRouteChangeMode.pause), ['pause']);
    });

    testWidgets('stop mode stops', (tester) async {
      expect(await endTrack(AudioRouteChangeMode.stop), ['stop']);
    });

    testWidgets('the next stop() hands over the take stop mode ended', (
      tester,
    ) async {
      await endTrack(AudioRouteChangeMode.stop);

      expect(await delegate.stop(), 'blob:take1');
      expect(delegate.calls, ['stop'], reason: 'no second stop');
      expect(await delegate.stop(), 'blob:take2', reason: 'handed over once');
    });

    testWidgets('listens to every track of the stream', (tester) async {
      final stream = createStream();
      // Add a second track, since a device may expose more than one.
      stream.addTrack(firstTrack(createStream()));
      delegate.recordConfig = const RecordConfig();

      delegate.listenRouteChange(stream);
      for (final track in stream.getAudioTracks().toDart) {
        track.dispatchEvent(web.Event('ended'));
      }
      await settle();

      expect(delegate.calls, ['pause', 'pause']);
    });

    testWidgets('our own stop() does not call back', (tester) async {
      final stream = createStream();
      final track = firstTrack(stream);
      delegate.recordConfig = const RecordConfig();

      delegate.listenRouteChange(stream);
      await delegate.resetContext(null, stream);

      expect(track.onended, isNull);
      expect(delegate.calls, isEmpty);
    });
  });

  group('swapToDefaultDevice', () {
    testWidgets('connects the new source and drops the previous one', (
      tester,
    ) async {
      final previousStream = createStream();
      final previousTrack = firstTrack(previousStream);
      final newStream = createStream();
      delegate = _TestDelegate(onReacquire: (_) async => newStream)
        ..audioContext = context
        ..mediaStream = previousStream
        ..source = context.createMediaStreamSource(previousStream)
        ..recordConfig = const RecordConfig();

      expect(await delegate.swapToDefaultDevice(), isTrue);

      expect(delegate.mediaStream, same(newStream));
      expect(delegate.wired, [same(delegate.source)]);
      expect(previousTrack.readyState, 'ended');
      expect(previousStream.getAudioTracks().toDart, isEmpty);
    });

    testWidgets('listens to the new stream', (tester) async {
      final newStream = createStream();
      delegate = _TestDelegate(onReacquire: (_) async => newStream)
        ..audioContext = context
        ..recordConfig = const RecordConfig();

      await delegate.swapToDefaultDevice();
      firstTrack(newStream).dispatchEvent(web.Event('ended'));
      await settle();

      expect(delegate.calls, ['swapped', 'pause']);
    });

    testWidgets('reports the default device', (tester) async {
      const mic = InputDevice(id: 'usb-mic', label: 'USB mic');
      final reported = <RecordConfig>[];
      delegate = _TestDelegate(onReacquire: (_) async => createStream())
        ..audioContext = context
        ..recordConfig = const RecordConfig(device: mic)
        ..onConfigChanged = reported.add;

      await delegate.swapToDefaultDevice();

      expect(reported.single.device, isNull);
      expect(delegate.recordConfig?.device, isNull);
    });

    testWidgets('gives up when stop() drops the context meanwhile', (
      tester,
    ) async {
      final newStream = createStream();
      delegate =
          _TestDelegate(
              onReacquire: (_) async {
                delegate.audioContext = null;
                return newStream;
              },
            )
            ..audioContext = context
            ..recordConfig = const RecordConfig();

      expect(await delegate.swapToDefaultDevice(), isFalse);

      expect(delegate.wired, isEmpty);
      expect(newStream.getAudioTracks().toDart, isEmpty);
    });

    testWidgets('releases the new stream when wiring throws', (tester) async {
      final newStream = createStream();
      delegate =
          _TestDelegate(onReacquire: (_) async => newStream, failWiring: true)
            ..audioContext = context
            ..recordConfig = const RecordConfig();

      expect(await delegate.swapToDefaultDevice(), isFalse);

      expect(newStream.getAudioTracks().toDart, isEmpty);
    });

    testWidgets('runs one swap at a time', (tester) async {
      var reacquired = 0;
      delegate =
          _TestDelegate(
              onReacquire: (_) async {
                reacquired++;
                return createStream();
              },
            )
            ..audioContext = context
            ..recordConfig = const RecordConfig();

      final results = await Future.wait([
        delegate.swapToDefaultDevice(),
        delegate.swapToDefaultDevice(),
      ]);

      expect(results, [isTrue, isTrue]);
      expect(reacquired, 1);

      expect(await delegate.swapToDefaultDevice(), isTrue);
      expect(reacquired, 2, reason: 'a later swap runs again');
    });

    testWidgets('fails without a take', (tester) async {
      delegate = _TestDelegate(onReacquire: (_) async => createStream());

      expect(await delegate.swapToDefaultDevice(), isFalse);
    });
  });

  group('reattach', () {
    const mic = InputDevice(id: 'usb-mic', label: 'USB mic');

    // Returns the device each getUserMedia call asked for; null is the default one.
    List<String?> reattachWith({
      required RecordConfig config,
      required bool micIsBack,
      List<RecordConfig>? reported,
    }) {
      final asked = <String?>[];
      delegate =
          _TestDelegate(
              onReacquire: (config) async {
                asked.add(config.device?.id);
                if (config.device != null && !micIsBack) {
                  throw StateError('not found');
                }
                return createStream();
              },
            )
            ..audioContext = context
            ..recordConfig = config
            ..requestedDevice = mic
            ..onConfigChanged = reported?.add;
      return asked;
    }

    testWidgets('goes back to the requested device once it returned', (
      tester,
    ) async {
      final reported = <RecordConfig>[];
      final asked = reattachWith(
        config: const RecordConfig(device: mic),
        micIsBack: true,
        reported: reported,
      );

      expect(await delegate.reattach(), isTrue);

      expect(asked, ['usb-mic']);
      expect(reported, isEmpty);
    });

    testWidgets('falls back to the default device', (tester) async {
      final reported = <RecordConfig>[];
      final asked = reattachWith(
        config: const RecordConfig(device: mic),
        micIsBack: false,
        reported: reported,
      );

      expect(await delegate.reattach(), isTrue);

      expect(asked, ['usb-mic', null]);
      expect(reported.single.device, isNull);
    });

    // A follow move cleared the device, and the requested one came back since.
    testWidgets('reports the requested device back', (tester) async {
      final reported = <RecordConfig>[];
      reattachWith(
        config: const RecordConfig(),
        micIsBack: true,
        reported: reported,
      );

      expect(await delegate.reattach(), isTrue);

      expect(reported.single.device?.id, 'usb-mic');
    });
  });

  group('reportDevice', () {
    const mic = InputDevice(id: 'usb-mic', label: 'USB mic');

    testWidgets('reports the default device when another was asked for', (
      tester,
    ) async {
      final reported = <RecordConfig>[];

      final moved = delegate.reportDevice(
        const RecordConfig(device: mic),
        null,
        reported.add,
      );

      expect(moved.device, isNull);
      expect(reported, hasLength(1));
      expect(reported.single.device, isNull);
    });

    testWidgets('reports nothing when already on that device', (tester) async {
      final reported = <RecordConfig>[];
      const config = RecordConfig(device: mic);

      final moved = delegate.reportDevice(config, mic, reported.add);

      expect(moved, same(config));
      expect(reported, isEmpty);
    });

    // `reportDevice` must keep the fields `adjustConfig` already changed.
    testWidgets('keeps the other fields', (tester) async {
      final moved = delegate.reportDevice(
        const RecordConfig(device: mic, sampleRate: 16000, numChannels: 1),
        null,
        null,
      );

      expect(moved.sampleRate, 16000);
      expect(moved.numChannels, 1);
    });
  });

  group('resetContext', () {
    testWidgets('stops and removes the tracks', (tester) async {
      final stream = createStream();
      final track = firstTrack(stream);

      await delegate.resetContext(null, stream);

      expect(track.readyState, 'ended');
      expect(stream.getAudioTracks().toDart, isEmpty);
    });

    testWidgets('closes the context', (tester) async {
      await delegate.resetContext(context, null);

      expect(context.state, 'closed');
    });

    testWidgets('does not throw on an already closed context', (tester) async {
      await context.close().toDart;

      await delegate.resetContext(context, null);

      expect(context.state, 'closed');
    });

    testWidgets('accepts no context and no stream', (tester) async {
      await delegate.resetContext(null, null);
    });
  });
}

/// Fakes a delegate for the shared route-change code; [onReacquire] replaces getUserMedia, so tests need no mic.
class _TestDelegate extends RecorderDelegate {
  final Future<web.MediaStream> Function(RecordConfig config)? onReacquire;
  final bool failWiring;

  final calls = <String>[];
  final wired = <web.MediaStreamAudioSourceNode>[];

  @override
  web.AudioContext? audioContext;
  @override
  web.MediaStream? mediaStream;
  @override
  web.MediaStreamAudioSourceNode? source;
  @override
  RecordConfig? recordConfig;
  @override
  void Function(RecordConfig)? onConfigChanged;

  _TestDelegate({this.onReacquire, this.failWiring = false});

  @override
  Future<web.MediaStream> reacquireMediaStream(RecordConfig config) {
    final handler = onReacquire;

    return handler == null
        ? super.reacquireMediaStream(config)
        : handler(config);
  }

  @override
  void wireSource(web.MediaStreamAudioSourceNode source) {
    if (failWiring) throw StateError('wiring failed');
    wired.add(source);
  }

  @override
  void onSourceSwapped(
    web.MediaStreamAudioSourceNode source,
    web.MediaStream mediaStream,
    RecordConfig config,
  ) {
    calls.add('swapped');
    this.source = source;
    this.mediaStream = mediaStream;
    recordConfig = config;
  }

  @override
  Future<void> pause() async => calls.add('pause');

  // Stands in for a delegate's stop(): the take's URL counts the stops.
  @override
  Future<String?> stop() async {
    if (takeRouteStop() case final stopped?) return stopped;

    calls.add('stop');
    return 'blob:take${calls.where((call) => call == 'stop').length}';
  }

  @override
  Future<void> dispose() => throw UnimplementedError();

  @override
  Future<Amplitude> getAmplitude() => throw UnimplementedError();

  @override
  Future<bool> isPaused() => throw UnimplementedError();

  @override
  Future<bool> isRecording() => throw UnimplementedError();

  @override
  Future<void> resume() => throw UnimplementedError();

  @override
  Future<void> start(RecordConfig config, {required String path}) =>
      throw UnimplementedError();

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      throw UnimplementedError();
}
