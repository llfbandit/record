import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

import 'src/capture_pipeline.dart';
import 'src/codec_caps.dart';
import 'src/pactl_devices.dart';

class RecordLinux extends RecordPlatform {
  static void registerWith() {
    RecordPlatform.instance = RecordLinux();
  }

  final _pipeline = CapturePipeline();

  RecordState _state = RecordState.stop;
  String? _path;
  StreamController<RecordState>? _stateStreamCtrl;
  void Function(RecordConfig config)? _configChangedHandler;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {
    await stop(recorderId);

    await _stateStreamCtrl?.close();
    _stateStreamCtrl = null;
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) {
    return Future.value(_pipeline.amplitude.amplitude);
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
    return Future.value(_state == RecordState.pause);
  }

  @override
  Future<bool> isRecording(String recorderId) {
    return Future.value(_state == RecordState.record);
  }

  @override
  Future<void> pause(String recorderId) async {
    if (_state == RecordState.record) {
      _pipeline.pause();
      _updateState(RecordState.pause);
    }
  }

  @override
  Future<void> resume(String recorderId) async {
    if (_state == RecordState.pause) {
      _pipeline.resume();
      _updateState(RecordState.record);
    }
  }

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    await stop(recorderId);

    _supportedOrThrow(config);

    _deleteFile(path);

    await _pipeline.startFile(_adjustConfig(config), path);

    _path = path;
    _updateState(RecordState.record);
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    await stop(recorderId);

    final stream = await _pipeline.startStream(_adjustConfig(config));

    _updateState(RecordState.record);

    return stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    final path = _path;

    await _pipeline.stop();

    _path = null;

    _updateState(RecordState.stop);

    return path;
  }

  @override
  Future<void> cancel(String recorderId) async {
    final path = await stop(recorderId);

    _deleteFile(path);
  }

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) {
    return listPactlInputDevices();
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) {
    _stateStreamCtrl ??= StreamController.broadcast();
    return _stateStreamCtrl!.stream;
  }

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {
    _configChangedHandler = handler;
  }

  void _deleteFile(String? path) {
    if (path == null) return;

    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  void _supportedOrThrow(RecordConfig config) {
    if (!supportsEncoder(config.encoder)) {
      throw Exception('${config.encoder} is not supported.');
    }
  }

  RecordConfig _adjustConfig(RecordConfig config) {
    final adjusted = adjustConfig(config);

    if (!identical(adjusted, config)) _configChangedHandler?.call(adjusted);

    return adjusted;
  }

  void _updateState(RecordState state) {
    if (_state == state) return;

    _state = state;

    if (_stateStreamCtrl case final controller? when controller.hasListener) {
      controller.add(state);
    }
  }
}
