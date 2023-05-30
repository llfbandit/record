import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/mime_types.dart';

import 'audio_context.dart';

const _kMaxAmplitude = 0.0;
const _kMinAmplitude = -160.0;

class Recorder {
  // Media recorder object
  html.MediaRecorder? _mediaRecorder;
  // Media stream get from getUserMedia
  html.MediaStream? _mediaStream;
  // Audio data
  List<html.Blob> _chunks = [];
  // Completer to get data & stop events before `stop()` method ends
  Completer<String>? _onStopCompleter;
  StreamController<RecordState>? _stateStreamCtrl;
  StreamController<Uint8List>? _recordStreamCtrl;

  // Amplitude
  double _maxAmplitude = _kMinAmplitude;
  AudioContext? _audioCtx;
  AnalyserNode? _analyser;

  Future<void> dispose() async {
    _mediaRecorder?.stop();
    _stateStreamCtrl?.close();
    _recordStreamCtrl?.close();
    _reset();
  }

  Future<bool> hasPermission() async {
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) return false;

    try {
      await mediaDevices.getUserMedia({'audio': true});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isPaused() async {
    return _mediaRecorder?.state == 'paused';
  }

  Future<bool> isRecording() async {
    final state = _mediaRecorder?.state;
    return state == 'recording' || state == 'paused';
  }

  Future<void> pause() async {
    if (_mediaRecorder?.state == 'recording') {
      _mediaRecorder?.pause();

      try {
        _audioCtx?.suspend();
      } catch (e) {
        debugPrint(e.toString());
      }

      _updateState(RecordState.pause);
    }
  }

  Future<void> resume() async {
    if (_mediaRecorder?.state == 'paused') {
      _mediaRecorder?.resume();

      try {
        _audioCtx?.resume();
      } catch (e) {
        debugPrint(e.toString());
      }

      _updateState(RecordState.record);
    }
  }

  Future<void> start(
    RecordConfig config, {
    required String path,
  }) async {
    return _start(config);
  }

  Future<Stream<Uint8List>> startStream(
    RecordConfig config,
  ) async {
    await _start(config, true);

    _recordStreamCtrl = StreamController();
    return _recordStreamCtrl!.stream;
  }

  Future<String?> stop() async {
    _onStopCompleter = Completer();

    _mediaRecorder?.stop();

    _updateState(RecordState.stop);

    return _onStopCompleter?.future;
  }

  Future<List<InputDevice>> listInputDevices() async {
    final devices = <InputDevice>[];

    final mediaDevices = html.window.navigator.mediaDevices;
    try {
      if (mediaDevices == null) {
        _onError('enumerateDevices() not supported.');
        return devices;
      }

      final deviceInfos = await mediaDevices.enumerateDevices();
      for (var info in deviceInfos) {
        if (info is html.MediaDeviceInfo &&
            info.kind == 'audioinput' &&
            info.deviceId != null &&
            info.label != null) {
          devices.add(InputDevice(id: info.deviceId!, label: info.label!));
        }
      }
    } catch (error) {
      _onError(error);
    }

    return devices;
  }

  Future<void> _start(RecordConfig config, [bool isStream = false]) async {
    _mediaRecorder?.stop();
    _reset();

    final constraints = {
      'audio': config.device == null
          ? true
          : {
              'deviceId': {'exact': config.device!.id}
            },
      'audioBitsPerSecond': config.bitRate,
      'bitsPerSecond': config.bitRate,
      'sampleRate': config.samplingRate,
      'channelCount': config.numChannels,
    };

    // Try to assign dedicated mime type.
    // If contrainst isn't set, browser will record with its default codec.
    final mimeType = _getSupportedMimeType(config.encoder);
    if (mimeType != null) {
      constraints['mimeType'] = mimeType;
    }

    try {
      _mediaStream = await html.window.navigator.mediaDevices?.getUserMedia(
        constraints,
      );
      if (_mediaStream != null) {
        _onStart(_mediaStream!, isStream);
      } else {
        debugPrint('Audio recording not supported.');
      }
    } catch (error) {
      _onError(error);
    }
  }

  void _onStart(html.MediaStream stream, [bool isStream = false]) {
    _mediaRecorder = html.MediaRecorder(stream);
    _mediaRecorder?.addEventListener(
      'dataavailable',
      isStream ? _onDataAvailableStream : _onDataAvailable,
    );
    _mediaRecorder?.addEventListener('stop', _onStop);
    _mediaRecorder?.start(200); // Will trigger dataavailable every 200ms

    _createAudioContext(stream);

    _updateState(RecordState.record);
  }

  Future<bool> isEncoderSupported(AudioEncoder encoder) {
    final type = _getSupportedMimeType(encoder);

    return Future.value(type != null ? true : false);
  }

  Future<Amplitude> getAmplitude() async {
    try {
      final amp = _getMaxAmplitude().clamp(_kMinAmplitude, _kMaxAmplitude);

      if (_maxAmplitude < amp) {
        _maxAmplitude = amp;
      }
      return Amplitude(current: amp, max: _maxAmplitude);
    } catch (e) {
      return Amplitude(current: _kMinAmplitude, max: _maxAmplitude);
    }
  }

  Stream<RecordState> onStateChanged() {
    _stateStreamCtrl ??= StreamController(
      onCancel: () {
        _stateStreamCtrl?.close();
        _stateStreamCtrl = null;
      },
    );

    return _stateStreamCtrl!.stream;
  }

  String? _getSupportedMimeType(AudioEncoder encoder) {
    final types = mimeTypes[encoder];
    if (types == null) return null;

    for (var type in types) {
      if (html.MediaRecorder.isTypeSupported(type)) {
        return type;
      }
    }

    return null;
  }

  void _onError(dynamic error) {
    _reset();
    debugPrint(error.toString());
  }

  void _onDataAvailable(html.Event event) {
    if (event is! html.BlobEvent) return;

    final data = event.data;

    if (data != null && data.size > 0) {
      _chunks.add(data);
    }
  }

  void _onDataAvailableStream(html.Event event) {
    final streamCtrl = _recordStreamCtrl;
    if (streamCtrl == null) return;

    if (event is! html.BlobEvent) return;

    final data = event.data;
    if (data != null && data.size > 0) {
      final fileReader = html.FileReader();

      fileReader.onLoad.listen((event) {
        final result = fileReader.result;

        if (result is Uint8List) {
          streamCtrl.add(result);
        }
      });

      fileReader.readAsArrayBuffer(data.slice());
    }
  }

  void _onStop(html.Event event) {
    String? audioUrl;

    if (_chunks.isNotEmpty) {
      final blob = html.Blob(_chunks);
      audioUrl = html.Url.createObjectUrl(blob);
    }

    _reset();

    _onStopCompleter?.complete(audioUrl);
  }

  void _reset() {
    _mediaRecorder?.removeEventListener('dataavailable', _onDataAvailable);
    _mediaRecorder?.removeEventListener('onstop', _onStop);
    _mediaRecorder = null;
    _maxAmplitude = _kMinAmplitude;

    final tracks = _mediaStream?.getTracks();

    if (tracks != null) {
      for (var track in tracks) {
        track.stop();
      }

      _mediaStream = null;
    }

    _chunks = [];

    try {
      if (_audioCtx != null && _audioCtx!.state != 'closed') {
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

  void _updateState(RecordState state) {
    final ctrl = _stateStreamCtrl;
    if (ctrl == null) return;

    if (ctrl.hasListener && !ctrl.isClosed) {
      ctrl.add(state);
    }
  }

  void _createAudioContext(html.MediaStream stream) {
    var audioCtx = AudioContext();
    var source = audioCtx.createMediaStreamSource(stream);

    var analyser = audioCtx.createAnalyser();
    analyser.minDecibels = _kMinAmplitude;
    analyser.maxDecibels = _kMaxAmplitude;
    analyser.fftSize = 1024; // NB of samples (must be power of 2)
    analyser.smoothingTimeConstant = 0.3; // Default 0.8 is way too high
    source.connect(analyser);

    _audioCtx = audioCtx;
    _analyser = analyser;
  }

  double _getMaxAmplitude() {
    final analyser = _analyser;
    if (analyser == null) return _kMinAmplitude;

    final bufferLength = analyser.frequencyBinCount; // Always fftSize / 2
    final dataArray = Float32List(bufferLength.toInt());

    analyser.getFloatFrequencyData(dataArray);

    return dataArray.reduce(math.max);
  }
}
