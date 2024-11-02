import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'package:record_web/js/js_import_library.dart';
import 'package:record_web/js/js_webm_duration_fix.dart';
import 'package:web/web.dart' as web;

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/mime_types.dart';
import 'package:record_web/recorder/delegate/recorder_delegate.dart';
import 'package:record_web/recorder/recorder.dart';

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

  final OnStateChanged onStateChanged;
  RecordConfig? _config;

  MediaRecorderDelegate({required this.onStateChanged}) {
    ImportJsLibrary().import(
      './assets/packages/record_web/assets/js/record.fixwebmduration.js',
      jsFixWebmDurationContentId(),
    );
  }

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
      _mediaRecorder?.pause();
      _elapsedTime.stop();

      try {
        _audioCtx?.suspend();
      } catch (e) {
        debugPrint(e.toString());
      }

      onStateChanged(RecordState.pause);
    }
  }

  @override
  Future<void> resume() async {
    if (_mediaRecorder?.state == 'paused') {
      _mediaRecorder?.resume();
      _elapsedTime.start();

      try {
        _audioCtx?.resume();
      } catch (e) {
        debugPrint(e.toString());
      }

      onStateChanged(RecordState.record);
    }
  }

  @override
  Future<void> start(
    RecordConfig config, {
    required String path,
  }) async {
    _mediaRecorder?.stop();
    await _reset();

    try {
      final mediaStream = await initMediaStream(config);

      // Try to assign dedicated mime type.
      final mimeType = getSupportedMimeType(config.encoder);
      if (mimeType == null) {
        throw '${config.encoder} not supported.';
      }

      final mediaRecorder = web.MediaRecorder(
        mediaStream,
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

      _createAudioContext(config, mediaStream);

      _mediaRecorder = mediaRecorder;
      _mediaStream = mediaStream;
      _config = config;

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
    if (_isRecording()) {
      _onStopCompleter = Completer();

      _mediaRecorder?.stop();

      return _onStopCompleter!.future;
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

    if (_chunks.isNotEmpty) {
      _elapsedTime.stop();

      final blob = switch (_config!.encoder) {
        AudioEncoder.opus => await fixWebmDuration(
            web.Blob(
              _chunks.toJS,
              web.BlobPropertyBag(type: _mediaRecorder!.mimeType),
            ),
            _elapsedTime.elapsedMilliseconds.toJS,
          ).toDart,
        _ => web.Blob(
            _chunks.toJS,
            web.BlobPropertyBag(type: _mediaRecorder!.mimeType),
          ),
      };

      audioUrl = web.URL.createObjectURL(blob);
    }

    await _reset();

    onStateChanged(RecordState.stop);

    _onStopCompleter?.complete(audioUrl);
  }

  Future<void> _reset() async {
    _elapsedTime.stop();
    _elapsedTime.reset();

    _mediaRecorder?.ondataavailable = null;
    _mediaRecorder?.onstop = null;

    _mediaRecorder = null;
    _maxAmplitude = kMinAmplitude;

    await resetContext(_audioCtx, _mediaStream);
    _mediaStream = null;
    _audioCtx = null;
    _analyser = null;

    _chunks = [];
    _config = null;
  }

  void _createAudioContext(RecordConfig config, web.MediaStream stream) {
    final audioCtx = web.AudioContext();

    final source = audioCtx.createMediaStreamSource(stream);

    final analyser = audioCtx.createAnalyser();
    analyser.minDecibels = kMinAmplitude;
    analyser.maxDecibels = kMaxAmplitude;
    analyser.fftSize = 1024; // NB of samples (must be power of 2)
    analyser.smoothingTimeConstant = 0.3; // Default 0.8 is way too high
    source.connect(analyser);

    _audioCtx = audioCtx;
    _analyser = analyser;
  }

  double _getMaxAmplitude() {
    final analyser = _analyser;
    if (analyser == null) return kMinAmplitude;

    final bufferLength = analyser.frequencyBinCount; // Always fftSize / 2
    final dataArray = Float32List(bufferLength.toInt());

    analyser.getFloatFrequencyData(dataArray.toJS);

    return dataArray
        .reduce((value, element) => math.max(value, element))
        .toDouble();
  }
}
