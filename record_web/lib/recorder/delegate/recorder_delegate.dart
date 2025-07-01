import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:web/web.dart' as web;

typedef OnStateChanged = void Function(RecordState state);

class AdjustedConfig {
  web.AudioContext context;
  int numChannels;

  AdjustedConfig({
    required this.context,
    required this.numChannels,
  });

  num get sampleRate => context.sampleRate;
}

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

  AdjustedConfig adjustConfig(
    web.MediaStream mediaStream,
    RecordConfig config,
  ) {
    final settings = _getTrackSettings(mediaStream);

    final result = AdjustedConfig(
      context: _adjustContext(settings),
      numChannels: _adjustNumChannels(config, settings),
    );

    if (kDebugMode) {
      if (config.numChannels != result.numChannels) {
        debugPrint('Channels adjusted to ${result.numChannels}');
      }
      if (config.sampleRate != result.sampleRate) {
        debugPrint('Sample rate adjusted to ${result.sampleRate}');
      }
    }

    return result;
  }

  web.AudioContext getContext(
    web.MediaStream mediaStream,
    RecordConfig config,
  ) {
    final settings = _getTrackSettings(mediaStream);
    return _adjustContext(settings);
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
        web.console.warn(e.toString().toJS);
      }
    }
  }

  /// Get actual track properties.
  web.MediaTrackSettings _getTrackSettings(web.MediaStream mediaStream) {
    final tracks = mediaStream.getAudioTracks().toDart;

    if (tracks.isEmpty) {
      throw Exception('No tracks. Unable to apply constraints.');
    }

    return tracks.first.getSettings();
  }

  web.AudioContext _adjustContext(web.MediaTrackSettings settings) {
    // Check for sampleRate support (i.e. Firefox)
    return settings.hasProperty('sampleRate'.toJS).toDart
        ? web.AudioContext(
            web.AudioContextOptions(sampleRate: settings.sampleRate.toDouble()),
          )
        : web.AudioContext();
  }

  int _adjustNumChannels(RecordConfig config, web.MediaTrackSettings settings) {
    // Check for channelCount support (i.e. Safari)
    return settings.hasProperty('channelCount'.toJS).toDart
        ? settings.channelCount
        : config.numChannels;
  }
}
