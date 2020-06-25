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
    int samplingRate = 44000,
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
  AAC,
  AMR_NB,
  AMR_WB,
  MPEG_4,
}

enum AudioEncoder {
  AAC,
  AMR_NB,
  AMR_WB,
}
