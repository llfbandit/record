import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:web/web.dart' as web;

typedef OnStateChanged = void Function(RecordState state);

class AdjustedConfig {
  web.AudioContext context;
  int numChannels;
  num sampleRate;

  AdjustedConfig({
    required this.context,
    required this.numChannels,
    required this.sampleRate,
  });
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
    final tracks = mediaStream.getAudioTracks().toDart;

    if (tracks.isEmpty) {
      throw Exception('No tracks. Unable to apply constraints.');
    }

    // Get actual track properties.
    final settings = tracks.first.getSettings();

    // Check for sampleRate support (i.e. Firefox)
    final supportSampleRate = settings.hasProperty('sampleRate'.toJS).toDart;

    final AdjustedConfig result;

    if (supportSampleRate) {
      result = AdjustedConfig(
        context: web.AudioContext(
          web.AudioContextOptions(sampleRate: settings.sampleRate.toDouble()),
        ),
        numChannels: settings.channelCount,
        sampleRate: settings.sampleRate,
      );
    } else {
      final context = web.AudioContext();
      result = AdjustedConfig(
        context: context,
        numChannels: settings.channelCount,
        sampleRate: context.sampleRate,
      );
    }

    if (kDebugMode) {
      if (!supportSampleRate) {
        debugPrint(
          'Browser doesn\'t support sampleRate. Recording may be inaccurate.',
        );
      }
      if (config.numChannels != result.numChannels) {
        debugPrint('Channels adjusted to ${result.numChannels}');
      }
      if (config.sampleRate != result.sampleRate) {
        debugPrint('Sample rate adjusted to ${result.sampleRate}');
      }
    }

    return result;
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
