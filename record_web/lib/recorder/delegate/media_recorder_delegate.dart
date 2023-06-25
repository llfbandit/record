import 'dart:async';
import 'dart:math' as math;
import 'dart:js_util' as jsu;

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/js/js_import_library.dart';
import 'package:record_web/js/js_interop/audio_context.dart';
import 'package:record_web/js/js_interop/core.dart';
import 'package:record_web/js/js_webm_duration_fix.dart';
import 'package:record_web/mime_types.dart';
import 'package:record_web/recorder/delegate/recorder_delegate.dart';
import 'package:record_web/recorder/recorder.dart';

class MediaRecorderDelegate extends RecorderDelegate {
  // Media recorder object
  MediaRecorder? _mediaRecorder;
  // Media stream get from getUserMedia
  MediaStream? _mediaStream;
  // Audio data
  List<Blob> _chunks = [];
  // Completer to get data & stop events before `stop()` method ends
  Completer<String?>? _onStopCompleter;

  StreamController<Uint8List>? _recordStreamCtrl;
  final _elapsedTime = Stopwatch();

  // Amplitude
  double _maxAmplitude = kMinAmplitude;
  AudioContext? _audioCtx;
  AnalyserNode? _analyser;

  final OnStateChanged onStateChanged;

  MediaRecorderDelegate({required this.onStateChanged}) {
    ImportJsLibrary().import(
      jsFixWebmDurationContent(),
      jsFixWebmDurationContentId(),
    );
  }

  @override
  Future<void> dispose() async {
    await stop();
    _reset();
  }

  @override
  Future<bool> isPaused() async {
    return _mediaRecorder?.state == RecordingState.paused;
  }

  @override
  Future<bool> isRecording() async {
    return _isRecording();
  }

  @override
  Future<void> pause() async {
    if (_mediaRecorder?.state == RecordingState.recording) {
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
    if (_mediaRecorder?.state == RecordingState.paused) {
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
    _reset();

    final constraints = MediaStreamConstraints(
      audio: config.device == null
          ? true
          : {
              'deviceId': {'exact': config.device!.id}
            },
    );

    try {
      _mediaStream = await window.navigator.mediaDevices.getUserMedia(
        constraints,
      );
      if (_mediaStream != null) {
        final audioTracks = _mediaStream!.getAudioTracks();

        for (var track in audioTracks) {
          track.applyConstraints(MediaTrackConstraints(
            autoGainControl: config.autoGain,
            echoCancellation: config.echoCancel,
            noiseSuppression: config.noiseSuppress,
            sampleRate: config.sampleRate.toDouble(),
            channelCount: config.numChannels.toDouble(),
          ));
        }

        _onStart(_mediaStream!, config);
      } else {
        debugPrint('Audio recording not supported.');
      }
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

      onStateChanged(RecordState.stop);

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
    return state == RecordingState.recording || state == RecordingState.paused;
  }

  void _onStart(MediaStream stream, RecordConfig config) {
    // Try to assign dedicated mime type.
    // If contrainst isn't set, browser will record with its default codec.
    final mimeType = getSupportedMimeType(config.encoder);

    final mediaRecorder = MediaRecorder(
      stream,
      MediaRecorderOptions(
        audioBitsPerSecond: config.bitRate,
        bitsPerSecond: config.bitRate,
        mimeType: mimeType,
      ),
    );
    mediaRecorder.ondataavailable = jsu.allowInterop(_onDataAvailable);
    mediaRecorder.onstop = jsu.allowInterop(_onStop);

    _elapsedTime.start();

    mediaRecorder.start(200); // Will trigger dataavailable every 200ms

    _createAudioContext(stream);

    _mediaRecorder = mediaRecorder;

    onStateChanged(RecordState.record);
  }

  void _onError(dynamic error) {
    _reset();
    debugPrint(error.toString());
  }

  void _onDataAvailable(Event event) {
    if (event is! BlobEvent) return;

    final data = event.data;

    if (data.size > 0) {
      _chunks.add(data);
    }
  }

  Future<void> _onStop(Event event) async {
    String? audioUrl;

    if (_chunks.isNotEmpty) {
      debugPrint('Container/codec chosen: ${_mediaRecorder?.mimeType}');

      _elapsedTime.stop();

      var blob = await jsu.promiseToFuture(
        fixWebmDuration(
          Blob(
            _chunks,
            BlobPropertyBag(type: _mediaRecorder?.mimeType ?? 'audio/webm'),
          ),
          _elapsedTime.elapsedMilliseconds,
          null,
        ),
      );

      audioUrl = Url.createObjectURL(blob);
    }

    _reset();

    _onStopCompleter?.complete(audioUrl);
  }

  void _reset() {
    _elapsedTime.stop();
    _elapsedTime.reset();

    _mediaRecorder?.ondataavailable = null;
    _mediaRecorder?.onstop = null;

    _mediaRecorder = null;
    _maxAmplitude = kMinAmplitude;

    final tracks = _mediaStream?.getTracks();

    if (tracks != null) {
      for (var track in tracks) {
        track.stop();
        _mediaStream?.removeTrack(track);
      }

      _mediaStream = null;
    }

    _chunks = [];

    try {
      if (_audioCtx != null && _audioCtx!.state != AudioContextState.closed) {
        _audioCtx?.close();
      }
      _audioCtx = null;
      _analyser = null;
    } catch (e) {
      debugPrint(e.toString());
    }

    _recordStreamCtrl?.close();
    _recordStreamCtrl = null;
  }

  void _createAudioContext(MediaStream stream) {
    final audioCtx = AudioContext();
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

    analyser.getFloatFrequencyData(dataArray);

    return dataArray.reduce(math.max);
  }
}
