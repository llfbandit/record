import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:web/web.dart' as web;

typedef OnStateChanged = void Function(RecordState state);

class AdjustedConfig {
  final web.AudioContext context;
  final RecordConfig config;

  AdjustedConfig({required this.context, required this.config});
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

  Future<web.MediaStream> initMediaStream(RecordConfig config) async {
    final constraints = web.MediaStreamConstraints(
      audio: {
        'autoGainControl': config.autoGain,
        'echoCancellation': config.echoCancel,
        'noiseSuppression': config.noiseSuppress,
        'sampleRate': config.sampleRate,
        'sampleSize': 16,
        'channelCount': config.numChannels,
        if (config.device case final device?) 'deviceId': {'exact': device.id},
      }.jsify()!,
    );

    return web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;
  }

  /// [canConvert]: whether the pipeline resamples and remixes to the requested format.
  AdjustedConfig adjustConfig(
    web.MediaStream mediaStream,
    RecordConfig config, {
    required bool canConvert,
    void Function(RecordConfig)? onConfigChanged,
  }) {
    final settings = _getTrackSettings(mediaStream);
    final context = _adjustContext(settings);
    final sampleRate = canConvert
        ? config.sampleRate
        : context.sampleRate.toInt();
    final numChannels = _adjustNumChannels(config, settings, canConvert);
    final autoGain = _adjustBoolSetting(
      'autoGainControl',
      config.autoGain,
      settings,
    );
    final echoCancel = _adjustBoolSetting(
      'echoCancellation',
      config.echoCancel,
      settings,
    );
    final noiseSuppress = _adjustBoolSetting(
      'noiseSuppression',
      config.noiseSuppress,
      settings,
    );

    final changed =
        config.numChannels != numChannels ||
        config.sampleRate != sampleRate ||
        config.autoGain != autoGain ||
        config.echoCancel != echoCancel ||
        config.noiseSuppress != noiseSuppress;

    if (changed) {
      config = config.copyWith(
        sampleRate: sampleRate,
        numChannels: numChannels,
        autoGain: autoGain,
        echoCancel: echoCancel,
        noiseSuppress: noiseSuppress,
      );
      onConfigChanged?.call(config);
    }

    return AdjustedConfig(context: context, config: config);
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

  int _adjustNumChannels(
    RecordConfig config,
    web.MediaTrackSettings settings,
    bool canConvert,
  ) {
    // Check for channelCount support (i.e. Safari)
    if (!settings.hasProperty('channelCount'.toJS).toDart) {
      return config.numChannels;
    }

    // Never more than the track has.
    return canConvert
        ? min(config.numChannels, settings.channelCount)
        : settings.channelCount;
  }

  bool _adjustBoolSetting(
    String key,
    bool fallback,
    web.MediaTrackSettings settings,
  ) {
    return settings.hasProperty(key.toJS).toDart
        ? settings.getProperty<JSBoolean>(key.toJS).toDart
        : fallback;
  }
}
