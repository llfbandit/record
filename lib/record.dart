import 'dart:async';

import 'package:flutter/services.dart';

/// Record class bridging to native recorders given by platform SDKs.
///
/// The plugin is aware of activity lifecycle.
/// So exiting, your app or activity will stop the recording (but won't delete the
/// output file).
class Record {
  static const MethodChannel _channel = const MethodChannel(
    'com.llfbandit.record',
  );

  /// Starts new recording session.
  ///
  /// [path]: The output path file. Required.
  /// [encoder]: The audio encoder to be used for recording.
  /// [bitRate]: The audio encoding bit rate in bits per second.
  /// [samplingRate]: The sampling rate for audio in samples per second.
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

  /// Stops recording session and release internal recorder resource.
  static Future<void> stop() {
    return _channel.invokeMethod('stop');
  }

  /// Pauses recording session.
  ///
  /// Note: Usable on Android API >= 24(Nougat). Does nothing otherwise.
  static Future<void> pause() {
    return _channel.invokeMethod('pause');
  }

  /// Resumes recording session after [pause].
  ///
  /// Note: Usable on Android API >= 24(Nougat). Does nothing otherwise.
  static Future<void> resume() {
    return _channel.invokeMethod('resume');
  }

  /// Checks if there's valid recording session.
  /// So if session is paused, this method will still return [true].
  static Future<bool> isRecording() async {
    final result = await _channel.invokeMethod<bool>('isRecording');
    return result ?? false;
  }

  /// Checks if recording session is paused.
  static Future<bool> isPaused() async {
    final result = await _channel.invokeMethod<bool>('isPaused');
    return result ?? false;
  }

  /// Checks and requests for audio record permission.
  static Future<bool> hasPermission() async {
    final result = await _channel.invokeMethod<bool>('hasPermission');
    return result ?? false;
  }
}

/// Audio encoder to be used for recording.
enum AudioEncoder {
  /// Will output to MPEG_4 format container.
  AAC,

  /// Will output to MPEG_4 format container.
  AAC_LD,

  /// Will output to MPEG_4 format container.
  AAC_HE,

  /// sampling rate should be set to 8kHz.
  /// Will output to 3GP format container on Android.
  AMR_NB,

  /// sampling rate should be set to 16kHz.
  /// Will output to 3GP format container on Android.
  AMR_WB,

  /// Will output to MPEG_4 format container.
  /// /!\ SDK 29 on Android /!\
  /// /!\ SDK 11 on iOs /!\
  OPUS,
}
