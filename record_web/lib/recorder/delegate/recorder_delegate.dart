import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/js/js_interop/audio_context.dart';
import 'package:record_web/js/js_interop/core.dart';

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

  Future<(MediaStream, RecordConfig)> initMediaStream(
    RecordConfig config,
  ) async {
    final constraints = MediaStreamConstraints(
      audio: config.device == null
          ? true
          : {
              'deviceId': {'exact': config.device!.id}
            },
    );

    final mediaStream = await window.navigator.mediaDevices.getUserMedia(
      constraints,
    );
    final audioTracks = mediaStream.getAudioTracks();

    var adjustedConfig = config;

    for (var track in audioTracks) {
      adjustedConfig = _adjustConfig(track, config);

      track.applyConstraints(MediaTrackConstraints(
        autoGainControl: adjustedConfig.autoGain,
        echoCancellation: adjustedConfig.echoCancel,
        noiseSuppression: adjustedConfig.noiseSuppress,
        sampleRate: adjustedConfig.sampleRate.toDouble(),
        channelCount: adjustedConfig.numChannels.toDouble(),
      ));
    }

    return (mediaStream, adjustedConfig);
  }

  Future<void> resetContext(
    AudioContext? audioCtx,
    MediaStream? mediaStream,
  ) async {
    final ms = mediaStream;

    if (ms != null) {
      final tracks = ms.getTracks();

      for (var track in tracks) {
        track.stop();
        ms.removeTrack(track);
      }
    }

    final ctx = audioCtx;
    if (ctx != null) {
      try {
        if (ctx.state != AudioContextState.closed) {
          await ctx.close();
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    }
  }

  RecordConfig _adjustConfig(MediaStreamTrack track, RecordConfig config) {
    try {
      final capabilities = track.getCapabilities();

      return RecordConfig(
        bitRate: config.bitRate,
        device: config.device,
        encoder: config.encoder,
        autoGain: config.autoGain
            ? capabilities.autoGainControl.any((e) => e == true)
            : false,
        echoCancel: config.echoCancel
            ? capabilities.echoCancellation.any((e) => e == true)
            : false,
        noiseSuppress: config.noiseSuppress
            ? capabilities.noiseSuppression.any((e) => e == true)
            : false,
        sampleRate: min(
          max(config.sampleRate, capabilities.sampleRate.min),
          capabilities.sampleRate.max,
        ),
        numChannels: min(
          max(config.sampleRate, capabilities.channelCount.min),
          capabilities.channelCount.max,
        ),
      );
    } catch (error) {
      debugPrint('getCapabilities error:\n$error');
    }

    return config;
  }
}
