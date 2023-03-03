import 'dart:async';

import 'package:flutter/services.dart';
import 'package:record_platform_interface/src/record_platform_interface.dart';
import 'package:record_platform_interface/src/types/types.dart';

class MethodChannelRecord extends RecordPlatform {
  // Channel handlers
  final _methodChannel = const MethodChannel('com.llfbandit.record/messages');
  final _eventChannel = const EventChannel('com.llfbandit.record/events');
  final _eventRecordChannel = const EventChannel(
    'com.llfbandit.record/eventsRecord',
  );

  StreamSubscription<List<int>>? _recordStreamSub;
  StreamController<List<int>>? _recordStreamCtrl;

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
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
    int numChannels = 2,
    InputDevice? device,
  }) {
    return _methodChannel.invokeMethod('start', {
      'path': path,
      'encoder': encoder.name,
      'bitRate': bitRate,
      'samplingRate': samplingRate,
      'numChannels': numChannels,
      'device': device?.toMap(),
    });
  }

  @override
  Future<Stream<List<int>>> startStream({
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
    int numChannels = 2,
    InputDevice? device,
  }) async {
    await _methodChannel.invokeMethod('startStream', {
      'encoder': encoder.name,
      'bitRate': bitRate,
      'samplingRate': samplingRate,
      'numChannels': numChannels,
      'device': device?.toMap(),
    });

    return _startListeningRecordStream();
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
    final devices =
        await _methodChannel.invokeMethod<List<dynamic>>('listInputDevices');

    return devices
            ?.map((d) => InputDevice.fromMap(d as Map))
            .toList(growable: false) ??
        [];
  }

  @override
  Stream<RecordState> onStateChanged() {
    return _eventChannel.receiveBroadcastStream().map<RecordState>(
          (state) => RecordState.values.firstWhere((e) => e.index == state),
        );
  }

  Future<Stream<List<int>>> _startListeningRecordStream() async {
    await _stopListeningRecordStream();

    final stream = _eventRecordChannel
        .receiveBroadcastStream()
        .map<List<int>>((data) => data);

    _recordStreamCtrl = StreamController();
    _recordStreamSub = stream.listen(_recordStreamCtrl?.add);

    return stream;
  }

  Future<void> _stopListeningRecordStream() async {
    await _recordStreamSub?.cancel();
    await _recordStreamCtrl?.close();
  }
}
