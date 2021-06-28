import 'package:flutter/services.dart';
import 'package:record_platform_interface/src/record_platform_interface.dart';
import 'package:record_platform_interface/src/types/amplitude.dart';
import 'package:record_platform_interface/src/types/audio_encoder.dart';

class MethodChannelRecord extends RecordPlatform {
  static const MethodChannel _channel = const MethodChannel(
    'com.llfbandit.record',
  );

  @override
  Future<bool> hasPermission() async {
    final result = await _channel.invokeMethod<bool>('hasPermission');
    return result ?? false;
  }

  @override
  Future<bool> isPaused() async {
    final result = await _channel.invokeMethod<bool>('isPaused');
    return result ?? false;
  }

  @override
  Future<bool> isRecording() async {
    final result = await _channel.invokeMethod<bool>('isRecording');
    return result ?? false;
  }

  @override
  Future<void> pause() {
    return _channel.invokeMethod('pause');
  }

  @override
  Future<void> resume() {
    return _channel.invokeMethod('resume');
  }

  @override
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.AAC,
    int bitRate = 128000,
    double samplingRate = 44100.0,
  }) {
    return _channel.invokeMethod('start', {
      "path": path,
      "encoder": encoder.index,
      "bitRate": bitRate,
      "samplingRate": samplingRate,
    });
  }

  @override
  Future<String?> stop() {
    return _channel.invokeMethod('stop');
  }

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
  }

  @override
  Future<Amplitude> getAmplitude() async {
    final result = await _channel.invokeMethod('getAmplitude');

    return Amplitude(
      current: result?['current'] ?? 0.0,
      max: result?['max'] ?? 0.0,
    );
  }
}
