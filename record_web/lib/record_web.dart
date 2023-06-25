import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/recorder/recorder.dart';

class RecordPluginWeb {
  static void registerWith(Registrar registrar) {
    RecordPlatform.instance = RecordPluginWebWrapper();
  }
}

class RecordPluginWebWrapper extends RecordPlatform {
  // recorders from recorderId
  final _recorders = <String, Recorder>{};

  @override
  Future<void> create(String recorderId) async {
    _recorders[recorderId] = Recorder();
  }

  @override
  Future<void> dispose(String recorderId) async {
    final recorder = _getRecorder(recorderId);
    await recorder.dispose();

    _recorders.remove(recorderId);
  }

  @override
  Future<bool> hasPermission(String recorderId) {
    return _getRecorder(recorderId).hasPermission();
  }

  @override
  Future<bool> isPaused(String recorderId) {
    return _getRecorder(recorderId).isPaused();
  }

  @override
  Future<bool> isRecording(String recorderId) {
    return _getRecorder(recorderId).isRecording();
  }

  @override
  Future<void> pause(String recorderId) {
    return _getRecorder(recorderId).pause();
  }

  @override
  Future<void> resume(String recorderId) {
    return _getRecorder(recorderId).resume();
  }

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) {
    return _getRecorder(recorderId).start(config, path: path);
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) {
    return _getRecorder(recorderId).startStream(config);
  }

  @override
  Future<String?> stop(String recorderId) {
    return _getRecorder(recorderId).stop();
  }

  @override
  Future<void> cancel(String recorderId) {
    return _getRecorder(recorderId).cancel();
  }

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) {
    return _getRecorder(recorderId).listInputDevices();
  }

  @override
  Future<bool> isEncoderSupported(String recorderId, AudioEncoder encoder) {
    return _getRecorder(recorderId).isEncoderSupported(encoder);
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) {
    return _getRecorder(recorderId).getAmplitude();
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) {
    return _getRecorder(recorderId).onStateChanged();
  }

  Recorder _getRecorder(String recorderId) {
    final recorder = _recorders[recorderId];

    if (recorder == null) {
      throw PlatformException(
        code: 'record',
        message:
            'Record has not yet been created or has already been disposed.',
      );
    }

    return recorder;
  }
}
