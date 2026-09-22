import 'dart:async';
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

/// Base for the web recorders: shared stream setup and route-change handling.
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

  // Each delegate exposes its capture graph so a route change can replace the input.
  web.AudioContext? get audioContext;
  web.MediaStream? get mediaStream;
  web.MediaStreamAudioSourceNode? get source;
  RecordConfig? get recordConfig;
  void Function(RecordConfig)? get onConfigChanged;

  /// Feeds [source] to the graph.
  void wireSource(web.MediaStreamAudioSourceNode source);

  /// Keeps the [source], [mediaStream] and [config] a route change moved capture to.
  void onSourceSwapped(
    web.MediaStreamAudioSourceNode source,
    web.MediaStream mediaStream,
    RecordConfig config,
  );

  // The device the take asked for: `reattach` goes back to it once it returns.
  InputDevice? requestedDevice;

  Future<bool>? _swap;
  Future<String?>? _routeStop;

  /// Gets a new stream for [config], after the device in use went away.
  Future<web.MediaStream> reacquireMediaStream(RecordConfig config) {
    return initMediaStream(config);
  }

  /// Moves capture to the default device; returns false when no device opens.
  Future<bool> swapToDefaultDevice() => _oneSwap(() => _swapTo(null));

  /// Moves capture back to [requestedDevice] if it returned, or else to the default one.
  Future<bool> reattach() => _oneSwap(() async {
    final requested = requestedDevice;
    return (requested != null && await _swapTo(requested)) ||
        await _swapTo(null);
  });

  // Overlapping swaps would each open a stream, and all but the last would leak.
  Future<bool> _oneSwap(Future<bool> Function() swap) {
    return _swap ??= swap().whenComplete(() => _swap = null);
  }

  Future<bool> _swapTo(InputDevice? device) async {
    final context = audioContext;
    final config = recordConfig;
    if (context == null || config == null) return false;

    web.MediaStream? newStream;
    web.MediaStreamAudioSourceNode? newSource;
    var swapped = false;
    try {
      newStream = await reacquireMediaStream(
        config.copyWith(device: (value: device)),
      );
      // The take may end while getUserMedia waits, so give up when the context changed.
      if (audioContext != context) return false;

      // Firefox throws for a device at another sample rate, so create the source before dropping the old one.
      newSource = context.createMediaStreamSource(newStream);
      source?.disconnect();
      await resetContext(null, mediaStream);
      if (audioContext != context) return false;

      wireSource(newSource);
      onSourceSwapped(
        newSource,
        newStream,
        reportDevice(config, device, onConfigChanged),
      );
      listenRouteChange(newStream);
      swapped = true;
      return true;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    } finally {
      // A stream left running would keep the mic indicator on.
      if (!swapped) {
        newSource?.disconnect();
        await resetContext(null, newStream);
      }
    }
  }

  /// Reports the move when capture lands on another device than [config] names; null is the default one.
  RecordConfig reportDevice(
    RecordConfig config,
    InputDevice? device,
    void Function(RecordConfig)? onConfigChanged,
  ) {
    if (config.device?.id == device?.id) return config;

    final moved = config.copyWith(device: (value: device));
    onConfigChanged?.call(moved);
    return moved;
  }

  /// Whether every track of [mediaStream] has ended, as after its device goes away.
  bool isSourceDead(web.MediaStream? mediaStream) {
    return mediaStream?.getAudioTracks().toDart.every(
          (track) => track.readyState == 'ended',
        ) ??
        true;
  }

  /// Applies `audioRouteChange` when a track ends on its own; `track.stop()` in `resetContext` never fires `ended`.
  void listenRouteChange(web.MediaStream stream) {
    for (final track in stream.getAudioTracks().toDart) {
      // Set `onended` rather than add a listener, so listening again replaces the old handler.
      track.onended = ((web.Event _) {
        unawaited(_onRouteChange());
      }).toJS;
    }
  }

  Future<void> _onRouteChange() async {
    try {
      switch (recordConfig?.audioRouteChange) {
        case AudioRouteChangeMode.follow:
          // Pause rather than stop when no device opens, so a later `resume()` can retry.
          if (!await swapToDefaultDevice()) await pause();
        case AudioRouteChangeMode.pause:
          await pause();
        case AudioRouteChangeMode.stop:
          await (_routeStop = stop());
        case null:
          break;
      }
    } catch (e) {
      // Nothing awaits the `ended` handler, so catch here or the error goes uncaught.
      debugPrint(e.toString());
    }
  }

  /// The take a route change stopped: its URL is the app's only way to it, so stop() hands it over.
  Future<String?>? takeRouteStop() {
    final stopped = _routeStop;
    _routeStop = null;
    return stopped;
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
        // Clear `onended` so the stopped track keeps no reference to this delegate.
        track.onended = null;
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
