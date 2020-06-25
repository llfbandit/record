import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Record {
  static const MethodChannel _channel = const MethodChannel(
    'com.llfbandit.record',
  );

  static Future<void> start({
    @required String path,
    AudioOutputFormat outputFormat = AudioOutputFormat.MPEG_4,
    AudioEncoder encoder = AudioEncoder.AAC,
    int bitRate = 128000,
    double samplingRate = 44100.0,
  }) {
    return _channel.invokeMethod('start', {
      "path": path,
      "outputFormat": outputFormat.index,
      "encoder": encoder.index,
      "bitRate": bitRate,
      "samplingRate": samplingRate,
    });
  }

  static Future<void> stop() {
    return _channel.invokeMethod('stop');
  }

  static Future<bool> isRecording() {
    return _channel.invokeMethod('isRecording');
  }

  static Future<bool> hasPermission() {
    return _channel.invokeMethod('hasPermission');
  }
}

enum AudioOutputFormat {
  /// sampling rate from 8 to 96kHz
  AAC,
  /// sampling rate should be set to 8kHz
  AMR_NB,
  /// sampling rate should be set to 16kHz
  AMR_WB,
  MPEG_4,
}

enum AudioEncoder {
  AAC,
  AMR_NB,
  AMR_WB,
}
