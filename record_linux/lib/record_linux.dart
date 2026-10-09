import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'src/codec_caps.dart';
import 'src/linux_recorder.dart';
import 'src/pactl_devices.dart';

class RecordLinux extends RecordPlatform {
  RecordLinux({@visibleForTesting LinuxRecorder Function()? newRecorder})
    : _newRecorder = newRecorder ?? LinuxRecorder.new;

  static void registerWith() {
    RecordPlatform.instance = RecordLinux();
  }

  final LinuxRecorder Function() _newRecorder;

  // One per AudioRecorder, so recorders never stop each other's capture.
  final _recorders = <String, LinuxRecorder>{};

  @override
  Future<void> create(String recorderId) async {
    _recorders[recorderId] = _newRecorder();
  }

  @override
  Future<void> dispose(String recorderId) async {
    final recorder = _getRecorder(recorderId);
    await recorder.dispose();

    _recorders.remove(recorderId);
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) {
    return Future.value(_getRecorder(recorderId).getAmplitude());
  }

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) {
    return Future.value(true);
  }

  @override
  Future<bool> isEncoderSupported(String recorderId, AudioEncoder encoder) {
    return Future.value(supportsEncoder(encoder));
  }

  @override
  Future<bool> isPaused(String recorderId) {
    return Future.value(_getRecorder(recorderId).isPaused());
  }

  @override
  Future<bool> isRecording(String recorderId) {
    return Future.value(_getRecorder(recorderId).isRecording());
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
    return listPactlInputDevices();
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) {
    return _getRecorder(recorderId).onStateChanged();
  }

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {
    _getRecorder(recorderId).setOnConfigChanged(handler);
  }

  LinuxRecorder _getRecorder(String recorderId) {
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
