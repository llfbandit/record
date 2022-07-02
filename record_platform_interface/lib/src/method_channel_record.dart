import 'package:flutter/services.dart';
import 'package:record_platform_interface/src/record_platform_interface.dart';
import 'package:record_platform_interface/src/types/amplitude.dart';
import 'package:record_platform_interface/src/types/audio_encoder.dart';
import 'package:record_platform_interface/src/types/input_device.dart';

class MethodChannelRecord extends RecordPlatform {
  final MethodChannel _channel = const MethodChannel(
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
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
    int numChannels = 2,
    InputDevice? device,
  }) {
    return _channel.invokeMethod('start', {
      'path': path,
      'encoder': encoder.name,
      'bitRate': bitRate,
      'samplingRate': samplingRate,
      'numChannels': numChannels,
      'device': device?.toMap(),
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

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _channel.invokeMethod<bool>(
      'isEncoderSupported',
      {'encoder': encoder.name},
    );

    return isSupported ?? false;
  }

  @override
  Future<List<InputDevice>> listInputDevices() async {
    final devices = await _channel.invokeMethod<List<Map>>('listInputDevices');

    if (devices == null) return [];

    return devices.map(InputDevice.fromMap).toList(growable: false);
  }
}
