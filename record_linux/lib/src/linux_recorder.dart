import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

import 'capture_pipeline.dart';
import 'codec_caps.dart';

/// One recorder: its own capture, state and config handler.
class LinuxRecorder {
  LinuxRecorder({CapturePipeline? pipeline})
    : _pipeline = pipeline ?? CapturePipeline();

  final CapturePipeline _pipeline;

  RecordState _state = RecordState.stop;
  String? _path;
  StreamController<RecordState>? _stateStreamCtrl;
  void Function(RecordConfig config)? _configChangedHandler;

  Future<void> dispose() async {
    await stop();

    await _stateStreamCtrl?.close();
    _stateStreamCtrl = null;
  }

  Amplitude getAmplitude() => _pipeline.amplitude.amplitude;

  bool isPaused() => _state == RecordState.pause;

  bool isRecording() => _state == RecordState.record;

  Future<void> pause() async {
    if (_state == RecordState.record) {
      _pipeline.pause();
      _updateState(RecordState.pause);
    }
  }

  Future<void> resume() async {
    if (_state == RecordState.pause) {
      _pipeline.resume();
      _updateState(RecordState.record);
    }
  }

  Future<void> start(RecordConfig config, {required String path}) async {
    await stop();

    _supportedOrThrow(config);

    _deleteFile(path);

    await _pipeline.startFile(_adjustConfig(config), path);

    _path = path;
    _updateState(RecordState.record);
  }

  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    await stop();

    final stream = await _pipeline.startStream(_adjustConfig(config));

    _updateState(RecordState.record);

    return stream;
  }

  Future<String?> stop() async {
    final path = _path;

    await _pipeline.stop();

    _path = null;

    _updateState(RecordState.stop);

    return path;
  }

  Future<void> cancel() async {
    final path = await stop();

    _deleteFile(path);
  }

  Stream<RecordState> onStateChanged() {
    _stateStreamCtrl ??= StreamController.broadcast();
    return _stateStreamCtrl!.stream;
  }

  void setOnConfigChanged(void Function(RecordConfig config)? handler) {
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
