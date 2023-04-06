import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/mime_types.dart';

class RecordPluginWeb extends RecordPlatform {
  static void registerWith(Registrar registrar) {
    RecordPlatform.instance = RecordPluginWeb();
  }

  // Media recorder object
  html.MediaRecorder? _mediaRecorder;
  // Media stream get from getUserMedia
  html.MediaStream? _mediaStream;
  // Audio data
  List<html.Blob> _chunks = [];
  // Completer to get data & stop events before `stop()` method ends
  Completer<String>? _onStopCompleter;
  StreamController<RecordState>? _stateStreamCtrl;
  StreamController<List<int>>? _recordStreamCtrl;

  @override
  Future<void> dispose() async {
    _mediaRecorder?.stop();
    _stateStreamCtrl?.close();
    _recordStreamCtrl?.close();
    _resetMediaRecorder();
  }

  @override
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

  @override
  Future<bool> isPaused() async {
    return _mediaRecorder?.state == 'paused';
  }

  @override
  Future<bool> isRecording() async {
    return _mediaRecorder?.state == 'recording';
  }

  @override
  Future<void> pause() async {
    _mediaRecorder?.pause();

    _updateState(RecordState.pause);
  }

  @override
  Future<void> resume() async {
    _mediaRecorder?.resume();

    _updateState(RecordState.record);
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    return _start(config);
  }

  @override
  Future<Stream<List<int>>> startStream(RecordConfig config) async {
    await _start(config);

    _recordStreamCtrl = StreamController();
    return _recordStreamCtrl!.stream;
  }

  @override
  Future<String?> stop() async {
    _onStopCompleter = Completer();

    _mediaRecorder?.stop();

    _updateState(RecordState.stop);

    return _onStopCompleter?.future;
  }

  @override
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
    _resetMediaRecorder();

    final constraints = {
      'audio': true,
      'audioBitsPerSecond': config.bitRate,
      'bitsPerSecond': config.bitRate,
      'sampleRate': config.samplingRate,
      'channelCount': config.numChannels,
      if (config.device != null) 'deviceId': {'exact': config.device!.id}
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
        _log('Audio recording not supported.');
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
    _mediaRecorder?.start();

    _updateState(RecordState.record);
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) {
    final type = _getSupportedMimeType(encoder);

    return Future.value(type != null ? true : false);
  }

  @override
  Future<Amplitude> getAmplitude() async {
    // TODO how to check amplitude values on web?
    return Amplitude(current: -160.0, max: -160.0);
  }

  @override
  @override
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
    _resetMediaRecorder();
    _log(error);
  }

  void _onDataAvailable(html.Event event) {
    if (event is html.BlobEvent && event.data != null) {
      _chunks.add(event.data!);
    }
  }

  void _onDataAvailableStream(html.Event event) {
    final streamCtrl = _recordStreamCtrl;
    if (streamCtrl == null) return;

    if (event is html.BlobEvent) {
      final data = event.data;
      if (data == null) return;

      final fileReader = html.FileReader();
      fileReader.readAsArrayBuffer(data);

      fileReader.onLoad.listen((event) {
        final result = fileReader.result;

        if (result is List<int>) {
          streamCtrl.add(result);
        }
      });
    }
  }

  void _onStop(html.Event event) {
    String? audioUrl;

    if (_chunks.isNotEmpty) {
      final blob = html.Blob(_chunks);
      audioUrl = html.Url.createObjectUrl(blob);
    }

    _resetMediaRecorder();

    _onStopCompleter?.complete(audioUrl);
  }

  void _resetMediaRecorder() {
    _mediaRecorder?.removeEventListener('dataavailable', _onDataAvailable);
    _mediaRecorder?.removeEventListener('onstop', _onStop);
    _mediaRecorder = null;

    final tracks = _mediaStream?.getTracks();

    if (tracks != null) {
      for (var track in tracks) {
        track.stop();
      }

      _mediaStream = null;
    }

    _chunks = [];

    _recordStreamCtrl?.close();
    _recordStreamCtrl = null;
  }

  void _log(String msg) {
    if (kDebugMode) print(msg);
  }

  void _updateState(RecordState state) {
    if (_stateStreamCtrl?.hasListener ?? false) {
      _stateStreamCtrl?.add(state);
    }
  }
}
