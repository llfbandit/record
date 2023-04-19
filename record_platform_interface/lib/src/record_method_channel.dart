import 'dart:async';

import 'package:flutter/services.dart';

import '../record_platform_interface.dart';

class RecordMethodChannel extends RecordPlatform {
  // Channel handlers
  final _methodChannel = const MethodChannel('com.llfbandit.record/messages');
  final _eventChannel = const EventChannel('com.llfbandit.record/events');
  final _eventRecordChannel = const EventChannel(
    'com.llfbandit.record/eventsRecord',
  );

  StreamController<List<int>>? _recordStreamCtrl;
  Stream<List<int>>? _recordStream;
  Stream<RecordState>? _stateStream;

  @override
  Future<bool> hasPermission() async {
    final result = await _methodChannel.invokeMethod<bool>('hasPermission');
    return result ?? false;
  }

  @override
  Future<bool> isPaused() async {
    final result = await _methodChannel.invokeMethod<bool>('isPaused');
    return result ?? false;
  }

  @override
  Future<bool> isRecording() async {
    final result = await _methodChannel.invokeMethod<bool>('isRecording');
    return result ?? false;
  }

  @override
  Future<void> pause() {
    return _methodChannel.invokeMethod('pause');
  }

  @override
  Future<void> resume() {
    return _methodChannel.invokeMethod('resume');
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) {
    return _methodChannel.invokeMethod('start', {
      'path': path,
      ...config.toMap(),
    });
  }

  @override
  Future<Stream<List<int>>> startStream(RecordConfig config) async {
    await _stopListeningRecordStream();

    if (_recordStream == null) {
      _recordStream = _eventRecordChannel
          .receiveBroadcastStream()
          .map<List<int>>((data) => data);

      _recordStream!.listen(
        (data) {
          final streamCtrl = _recordStreamCtrl;
          if (streamCtrl == null || streamCtrl.isClosed) return;
          streamCtrl.add(data);
        },
      );
    }

    _recordStreamCtrl = StreamController();

    await _methodChannel.invokeMethod('startStream', config.toMap());

    return _recordStreamCtrl!.stream;
  }

  @override
  Future<String?> stop() async {
    final outputPath = await _methodChannel.invokeMethod('stop');

    await _stopListeningRecordStream();

    return outputPath;
  }

  @override
  Future<void> dispose() async {
    await _methodChannel.invokeMethod('dispose');
    await _stopListeningRecordStream();
  }

  @override
  Future<Amplitude> getAmplitude() async {
    final result = await _methodChannel.invokeMethod('getAmplitude');

    return Amplitude(
      current: result?['current'] ?? 0.0,
      max: result?['max'] ?? 0.0,
    );
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _methodChannel.invokeMethod<bool>(
      'isEncoderSupported',
      {'encoder': encoder.name},
    );

    return isSupported ?? false;
  }

  @override
  Future<List<InputDevice>> listInputDevices() async {
    final devices = await _methodChannel.invokeMethod<List<dynamic>>(
      'listInputDevices',
    );

    return devices
            ?.map((d) => InputDevice.fromMap(d as Map))
            .toList(growable: false) ??
        [];
  }

  @override
  Stream<RecordState> onStateChanged() {
    _stateStream ??= _eventChannel.receiveBroadcastStream().map<RecordState>(
          (state) => RecordState.values.firstWhere((e) => e.index == state),
        );

    return _stateStream ?? Stream.value(RecordState.stop);
  }

  Future<void> _stopListeningRecordStream() async {
    await _recordStreamCtrl?.close();
    _recordStreamCtrl = null;
  }
}
