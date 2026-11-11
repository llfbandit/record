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
  // Audio data
  List<web.Blob> _chunks = [];
  // Completer to get data & stop events before `stop()` method ends
  Completer<String?>? _onStopCompleter;
  // Set when the browser fails the take: its stop event reports it.
  String? _failure;

  final _elapsedTime = Stopwatch();

  // Amplitude
  double _maxAmplitude = kMinAmplitude;
  web.AnalyserNode? _analyser;
  // MediaRecorder reads this node, so a new input swaps in without recreating it.
  web.MediaStreamAudioDestinationNode? _destination;

  final OnStateChanged onStateChanged;
  final OnStopped onStopped;
  @override
  final void Function(RecordConfig)? onConfigChanged;

  MediaRecorderDelegate({
    required this.onStateChanged,
    required this.onStopped,
    this.onConfigChanged,
  });

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

    // The take may stop while `reattachIfDead` waits.
    bool stillPaused() => _mediaRecorder?.state == 'paused';
    if (!await reattachIfDead(stillPaused)) return;

    // The browser may have suspended the context: resume it before `_mediaRecorder`, or the recorder captures silence.
    await audioContext?.resume().toDart;
    if (!stillPaused()) return;

    // Browsers may disconnect the source during a pause, so reconnect it.
    if (source case final source?) wireSource(source);

    _mediaRecorder?.resume();
    _elapsedTime.start();

    onStateChanged(RecordState.record);
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    _mediaRecorder?.stop();
    await _reset();

    try {
      final stream = await initMediaStream(config);
      mediaStream = stream;

      // MediaRecorder encodes the track as-is.
      final effectiveConfig = adjustConfig(
        stream,
        config,
        canConvert: false,
        onConfigChanged: onConfigChanged,
      );
      final context = effectiveConfig.context;
      audioContext = context;
      config = effectiveConfig.config;

      // Try to assign dedicated mime type.
      final mimeType = getSupportedMimeType(config.encoder);
      if (mimeType == null) {
        throw '${config.encoder} not supported.';
      }

      final destination = context.createMediaStreamDestination();
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
      mediaRecorder.onerror = _onRecorderError.toJS;
      _mediaRecorder = mediaRecorder;

      // MediaRecorder reads the context, so a suspended one records silence. Not awaited: a blocked resume waits for a user gesture.
      context.resume().toDart.ignore();

      final source = context.createMediaStreamSource(stream);
      _analyser = _createAnalyser(context);
      _destination = destination;
      this.source = source;
      recordConfig = config;
      requestedDevice = config.device;

      wireSource(source);

      listenRouteChange(stream);

      _elapsedTime.start();
      mediaRecorder.start(200); // Will trigger dataavailable every 200ms

      onStateChanged(RecordState.record);
    } catch (_) {
      await _reset();
      rethrow;
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
    // The context keeps running during a pause, so the analyser would still read the live mic.
    if (_mediaRecorder?.state != 'recording') {
      return Amplitude(current: kMinAmplitude, max: _maxAmplitude);
    }

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

  void _onRecorderError(web.Event event) {
    final message = event.isA<web.ErrorEvent>()
        ? (event as web.ErrorEvent).message
        : '';
    _failure = message.isEmpty ? 'Recording failed.' : message;
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
      final failure = _failure;
      final reason = takeStopReason();
      await _reset();
      onStopped(
        RecordStop(
          reason: failure == null ? reason : RecordStopReason.error,
          path: audioUrl,
          error: failure,
        ),
      );

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
    _mediaRecorder?.onerror = null;

    _mediaRecorder = null;
    _failure = null;
    _maxAmplitude = kMinAmplitude;

    // Clear the fields before awaiting `resetContext`, so an in-flight swap sees the take ended.
    final audioCtx = audioContext;
    final stream = mediaStream;
    mediaStream = null;
    audioContext = null;

    source?.disconnect();
    source = null;

    _destination = null;
    _analyser = null;
    recordConfig = null;

    _chunks = [];

    await resetContext(audioCtx, stream);
  }

  web.AnalyserNode _createAnalyser(web.AudioContext audioCtx) {
    final analyser = audioCtx.createAnalyser();
    analyser.fftSize = 1024;
    analyser.smoothingTimeConstant = 0.3; // Default 0.8 is way too high
    return analyser;
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
