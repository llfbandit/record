import 'dart:async';

import 'package:flutter/services.dart';

class Record {
  static const MethodChannel _channel = const MethodChannel(
    'com.llfbandit.record',
  );

  static Future<void> start({
    required String path,
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

  static Future<void> stop() {
    return _channel.invokeMethod('stop');
  }

  static Future<bool> isRecording() async {
    final result = await _channel.invokeMethod<bool>('isRecording');
    return result ?? false;
  }

  static Future<bool> hasPermission() async {
    final result = await _channel.invokeMethod<bool>('hasPermission');
    return result ?? false;
  }
}

enum AudioEncoder {
  /// Will output to MPEG_4 format container
  AAC,

  /// Will output to MPEG_4 format container
  AAC_LD,

  /// Will output to MPEG_4 format container
  AAC_HE,

  /// sampling rate should be set to 8kHz
  /// Will output to 3GP format container on Android
  AMR_NB,

  /// sampling rate should be set to 16kHz
  /// Will output to 3GP format container on Android
  AMR_WB,

  /// Will output to MPEG_4 format container
  /// /!\ SDK 29 on Android /!\
  /// /!\ SDK 11 on iOs /!\
  OPUS,
}
