import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/js/js_interop/audio_context.dart';

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

  Future<MediaStream> initMediaStream(
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

    for (var track in audioTracks) {
      await track.applyConstraints(MediaTrackConstraints(
        autoGainControl: config.autoGain,
        echoCancellation: config.echoCancel,
        noiseSuppression: config.noiseSuppress,
        sampleRate: config.sampleRate.toDouble(),
        channelCount: config.numChannels.toDouble(),
      ));
    }

    return mediaStream;
  }

  Future<void> resetContext(
    AudioContext? audioCtx,
    MediaStream? mediaStream,
  ) async {
    final ms = mediaStream;

    if (ms != null) {
      final tracks = ms.getAudioTracks();
      for (var track in tracks) {
        track.stop();
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
}
