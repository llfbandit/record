import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:web/web.dart' as web;

typedef OnStateChanged = void Function(RecordState state);

abstract class RecorderDelegate {
  Future<void> dispose();

  Future<Amplitude> getAmplitude();

  Future<bool> isPaused();

  Future<bool> isRecording();

  Future<void> pause();

  Future<void> resume();

  Future<void> start(RecordConfig config, {required String path});

  Future<Stream<Uint8List>> startStream(RecordConfig config);

  Future<String?> stop();

  Future<web.MediaStream> initMediaStream(
    RecordConfig config,
  ) async {
    final constraints = web.MediaStreamConstraints(
      audio: {
        'autoGainControl': config.autoGain,
        'echoCancellation': config.echoCancel,
        'noiseSuppression': config.noiseSuppress,
        'sampleRate': config.sampleRate,
        'sampleSize': 16,
        'channelCount': config.numChannels,
        if (config.device case final device?) 'deviceId': {'exact': device.id}
      }.jsify()!,
    );

    return web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;
  }

  Future<void> resetContext(
    web.AudioContext? audioCtx,
    web.MediaStream? mediaStream,
  ) async {
    final ms = mediaStream;

    if (ms != null) {
      final tracks = ms.getAudioTracks();
      for (var track in tracks.toDart) {
        track.stop();
        ms.removeTrack(track);
      }
    }

    final ctx = audioCtx;
    if (ctx != null) {
      try {
        if (ctx.state != 'closed') {
          await ctx.close().toDart;
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    }
  }
}
