import 'dart:async';

import 'package:record_platform_interface/record_platform_interface.dart';

/// Audio recorder API
class Record implements RecordPlatform {
  @override
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
  }) {
    return RecordPlatform.instance.start(
      path: path,
      encoder: encoder,
      bitRate: bitRate,
      samplingRate: samplingRate,
    );
  }

  @override
  Future<String?> stop() {
    return RecordPlatform.instance.stop();
  }

  @override
  Future<void> pause() {
    return RecordPlatform.instance.pause();
  }

  @override
  Future<void> resume() {
    return RecordPlatform.instance.resume();
  }

  @override
  Future<bool> isRecording() {
    return RecordPlatform.instance.isRecording();
  }

  @override
  Future<bool> isPaused() {
    return RecordPlatform.instance.isPaused();
  }

  @override
  Future<bool> hasPermission() {
    return RecordPlatform.instance.hasPermission();
  }

  @override
  Future<void> dispose() {
    return RecordPlatform.instance.dispose();
  }

  @override
  Future<Amplitude> getAmplitude() {
    return RecordPlatform.instance.getAmplitude();
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) {
    return RecordPlatform.instance.isEncoderSupported(encoder);
  }
}
