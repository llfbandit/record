import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'package:record_web/src/webm/webm_duration_fixer.dart';
import 'package:web/web.dart' as web;

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/src/mime_types.dart';
import 'package:record_web/src/recorder/delegate/recorder_delegate.dart';
import 'package:record_web/src/recorder/recorder.dart';

/// Records compressed formats with the browser's MediaRecorder.
class MediaRecorderDelegate extends RecorderDelegate {
  // Media recorder object
  web.MediaRecorder? _mediaRecorder;
  // Media stream get from getUserMedia
  web.MediaStream? _mediaStream;
  // Audio data
  List<web.Blob> _chunks = [];
  // Completer to get data & stop events before `stop()` method ends
  Completer<String?>? _onStopCompleter;

  final _elapsedTime = Stopwatch();

  // Amplitude
  double _maxAmplitude = kMinAmplitude;
  web.AudioContext? _audioCtx;
  web.AnalyserNode? _analyser;
  web.MediaStreamAudioSourceNode? _source;
  // MediaRecorder reads this node, so a new input swaps in without recreating it.
  web.MediaStreamAudioDestinationNode? _destination;
  RecordConfig? _config;

  final OnStateChanged onStateChanged;
  @override
  final void Function(RecordConfig)? onConfigChanged;

  MediaRecorderDelegate({required this.onStateChanged, this.onConfigChanged});

  @override
  Future<void> dispose() async {
    await stop();
    return _reset();
  }

  @override
  Future<bool> isPaused() async {
    return _mediaRecorder?.state == 'paused';
  }

  @override
  Future<bool> isRecording() async {
    return _isRecording();
  }

  @override
  Future<void> pause() async {
    if (_mediaRecorder?.state == 'recording') {
      // Keep the context running: suspended, it stops feeding `_destination` and the recorder counts the gap.
      _mediaRecorder?.pause();
      _elapsedTime.stop();

      onStateChanged(RecordState.pause);
    }
  }

  @override
  Future<void> resume() async {
    if (_mediaRecorder?.state != 'paused') return;

    // A removed device ends the paused track: move back to it or to the default one, or stay paused to retry.
    if (isSourceDead(_mediaStream) && !await reattach()) {
      throw const RecordResumeNoDeviceException();
    }

    // The browser may have suspended the context: resume it before `_mediaRecorder`, or the recorder captures silence.
    await _audioCtx?.resume().toDart;

    // Browsers may disconnect the source during a pause, so reconnect it.
    if (_source case final source?) wireSource(source);

    _mediaRecorder?.resume();
    _elapsedTime.start();

    onStateChanged(RecordState.record);
  }

  @override
  web.AudioContext? get audioContext => _audioCtx;

  @override
  web.MediaStream? get mediaStream => _mediaStream;

  @override
  web.MediaStreamAudioSourceNode? get source => _source;

  @override
  RecordConfig? get recordConfig => _config;

  @override
  void onSourceSwapped(
    web.MediaStreamAudioSourceNode source,
    web.MediaStream mediaStream,
    RecordConfig config,
  ) {
    _source = source;
    _mediaStream = mediaStream;
    _config = config;
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    _mediaRecorder?.stop();
    await _reset();

    try {
      final mediaStream = await initMediaStream(config);

      // MediaRecorder encodes the track as-is.
      final effectiveConfig = adjustConfig(
        mediaStream,
        config,
        canConvert: false,
        onConfigChanged: onConfigChanged,
      );
      config = effectiveConfig.config;

      // Try to assign dedicated mime type.
      final mimeType = getSupportedMimeType(config.encoder);
      if (mimeType == null) {
        throw '${config.encoder} not supported.';
      }

      final destination = effectiveConfig.context
          .createMediaStreamDestination();
      // The default 2 channels would upmix a mono mic, and later sources mix down to this count.
      destination.channelCount = config.numChannels;

      final mediaRecorder = web.MediaRecorder(
        destination.stream,
        web.MediaRecorderOptions(
          audioBitsPerSecond: config.bitRate,
          bitsPerSecond: config.bitRate,
          mimeType: mimeType,
        ),
      );
      mediaRecorder.ondataavailable =
          ((web.BlobEvent event) => _onDataAvailable(event)).toJS;
      mediaRecorder.onstop = ((web.Event event) => _onStop()).toJS;

      _elapsedTime.start();

      mediaRecorder.start(200); // Will trigger dataavailable every 200ms

      _setupAmplitudeAnalyser(effectiveConfig, mediaStream);

      _mediaRecorder = mediaRecorder;
      _mediaStream = mediaStream;
      _destination = destination;
      _config = config;
      requestedDevice = config.device;

      if (_source case final source?) wireSource(source);

      listenRouteChange(mediaStream);

      onStateChanged(RecordState.record);
    } catch (error) {
      _onError(error);
    }
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) {
    throw UnimplementedError();
  }

  @override
  Future<String?> stop() async {
    if (takeRouteStop() case final stopped?) return stopped;

    if (_isRecording()) {
      final completer = _onStopCompleter ??= Completer();

      _mediaRecorder?.stop();

      return completer.future;
    }

    return null;
  }

  @override
  Future<Amplitude> getAmplitude() async {
    try {
      final amp = _getMaxAmplitude().clamp(kMinAmplitude, kMaxAmplitude);

      if (_maxAmplitude < amp) {
        _maxAmplitude = amp;
      }
      return Amplitude(current: amp, max: _maxAmplitude);
    } catch (e) {
      return Amplitude(current: kMinAmplitude, max: _maxAmplitude);
    }
  }

  bool _isRecording() {
    final state = _mediaRecorder?.state;
    return state == 'recording' || state == 'paused';
  }

  /// Connects [source] to `_analyser` and `_destination`, dropping stale links first.
  @override
  void wireSource(web.MediaStreamAudioSourceNode source) {
    source.disconnect();
    if (_analyser case final analyser?) source.connect(analyser);
    if (_destination case final destination?) source.connect(destination);
  }

  void _onError(dynamic error) {
    _reset();
    debugPrint(error.toString());
  }

  void _onDataAvailable(web.BlobEvent event) {
    final data = event.data;

    if (data.size > 0) {
      _chunks.add(data);
    }
  }

  void _onStop() async {
    String? audioUrl;

    try {
      if (_chunks.isNotEmpty) {
        _elapsedTime.stop();

        final mimeType = _mediaRecorder!.mimeType;
        final mergedBlob = web.Blob(
          _chunks.toJS,
          web.BlobPropertyBag(type: mimeType),
        );
        final blob = mimeType.startsWith('audio/webm')
            ? await fixWebmDuration(
                mergedBlob,
                _elapsedTime.elapsedMilliseconds,
              )
            : mergedBlob;

        audioUrl = web.URL.createObjectURL(blob);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      await _reset();
      onStateChanged(RecordState.stop);

      if (_onStopCompleter case final completer?) {
        _onStopCompleter = null;

        if (!completer.isCompleted) {
          completer.complete(audioUrl);
        }
      }
    }
  }

  Future<void> _reset() async {
    _elapsedTime.stop();
    _elapsedTime.reset();

    _mediaRecorder?.ondataavailable = null;
    _mediaRecorder?.onstop = null;

    _mediaRecorder = null;
    _maxAmplitude = kMinAmplitude;

    // Clear the fields before awaiting `resetContext`, so an in-flight swap sees the take ended.
    final audioCtx = _audioCtx;
    final mediaStream = _mediaStream;
    _mediaStream = null;
    _audioCtx = null;

    _source?.disconnect();
    _source = null;

    _destination = null;
    _analyser = null;
    _config = null;

    _chunks = [];

    await resetContext(audioCtx, mediaStream);
  }

  void _setupAmplitudeAnalyser(
    AdjustedConfig effectiveConfig,
    web.MediaStream stream,
  ) {
    final audioCtx = effectiveConfig.context;

    final source = audioCtx.createMediaStreamSource(stream);

    final analyser = audioCtx.createAnalyser();
    analyser.fftSize = 1024;
    analyser.smoothingTimeConstant = 0.3; // Default 0.8 is way too high

    _audioCtx = audioCtx;
    _source = source;
    _analyser = analyser;
  }

  double _getMaxAmplitude() {
    final analyser = _analyser;
    if (analyser == null) return kMinAmplitude;

    final dataArray = Float32List(analyser.fftSize.toInt());
    final jsArray = dataArray.toJS;

    analyser.getFloatTimeDomainData(jsArray);

    final peak = jsArray.toDart.reduce((v, e) => math.max(v, e.abs()));
    if (peak == 0) return kMinAmplitude;

    return 20 * (math.log(peak) / math.ln10);
  }
}
