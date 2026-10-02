import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'capture_pipeline.dart';
import 'codec_caps.dart';
import 'pactl_devices.dart';
import 'route_monitor.dart';

/// One recorder: its own capture, state and config handler.
class LinuxRecorder {
  LinuxRecorder({CapturePipeline? pipeline})
    : _pipeline = pipeline ?? CapturePipeline();

  final CapturePipeline _pipeline;
  final _routeMonitor = RouteMonitor();

  RecordState _state = RecordState.stop;
  String? _path;
  // The take's config, whose device a route change may move.
  RecordConfig? _config;
  // The device the take asked for: resume() goes back to it once it returns.
  InputDevice? _requestedDevice;
  // Capture ended with its device: resume() needs a new one.
  bool _routeLost = false;
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
    if (_state != RecordState.pause) return;

    if (_routeLost) {
      final requested = _requestedDevice;
      final moved =
          (requested != null && await _moveTo(requested)) ||
          await _moveTo(null);
      if (!moved) throw const RecordResumeNoDeviceException();

      _routeLost = false;
    } else {
      _pipeline.resume();
    }

    _updateState(RecordState.record);
  }

  Future<void> start(RecordConfig config, {required String path}) async {
    await stop();

    _supportedOrThrow(config);

    _deleteFile(path);

    final adjusted = _adjustConfig(config);
    await _pipeline.startFile(adjusted, path);

    _path = path;
    await _beginTake(adjusted);
    _updateState(RecordState.record);
  }

  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    await stop();

    final adjusted = _adjustConfig(config);
    final stream = await _pipeline.startStream(adjusted);

    await _beginTake(adjusted);
    _updateState(RecordState.record);

    return stream;
  }

  Future<String?> stop() async {
    final path = _path;

    _config = null;
    _routeLost = false;
    _routeMonitor.stop();
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

  Future<void> _beginTake(RecordConfig config) async {
    _config = config;
    _requestedDevice = config.device;
    _routeLost = false;
    await _watchRoute();
  }

  Future<void> _watchRoute() async {
    final pid = _pipeline.capturePid;
    if (pid == null) return;

    try {
      await _routeMonitor.start(
        capturePid: pid,
        onRouteLost: () => unawaited(_onRouteLost()),
      );
    } catch (e) {
      // Without pactl, the take goes on without route handling.
      debugPrint(e.toString());
    }
  }

  Future<void> _onRouteLost() async {
    final config = _config;
    if (config == null) return;

    try {
      switch (config.audioRouteChange) {
        case AudioRouteChangeMode.follow when _state == RecordState.record:
          // Pause rather than stop when no device is left, so resume() can retry.
          // A stop() or start() while pactl runs ends this take: leave it be.
          if (!await _moveTo(null) && identical(config, _config)) {
            _suspendCapture();
          }
        case AudioRouteChangeMode.follow || AudioRouteChangeMode.pause:
          _suspendCapture();
        case AudioRouteChangeMode.stop:
          await stop();
      }
    } catch (e) {
      // Nothing awaits the monitor callback, so catch here.
      debugPrint(e.toString());
    }
  }

  // Keeps the file or stream open, so resume() can capture from a device again.
  void _suspendCapture() {
    _pipeline.suspendCapture();
    _routeLost = true;
    _updateState(RecordState.pause);
  }

  /// Restarts capture on [device], or on the default one when null, and
  /// reports the move; returns false when that device is missing.
  Future<bool> _moveTo(InputDevice? device) async {
    final config = _config;
    if (config == null) return false;

    final sources = await listPactlSourceNames();
    final available = device == null
        ? sources.isNotEmpty
        : sources.contains(device.id);
    // The take may end while pactl runs.
    if (!available || !identical(config, _config)) return false;

    final moved = config.copyWith(device: (value: device));
    await _pipeline.restartCapture(moved);
    if (!identical(config, _config)) return false;

    _config = moved;
    if (config.device?.id != device?.id) _configChangedHandler?.call(moved);
    await _watchRoute();

    return true;
  }

  void _updateState(RecordState state) {
    if (_state == state) return;

    _state = state;

    if (_stateStreamCtrl case final controller? when controller.hasListener) {
      controller.add(state);
    }
  }
}
