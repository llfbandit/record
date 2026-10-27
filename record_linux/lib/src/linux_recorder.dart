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
  LinuxRecorder({
    CapturePipeline? pipeline,
    this.listSources = listPactlSourceNames,
  }) : _pipeline = pipeline ?? CapturePipeline() {
    _pipeline.onExited = (error, {required capture}) =>
        unawaited(_onPipelineExited(error, capture: capture));
  }

  final CapturePipeline _pipeline;
  final Future<Set<String>> Function() listSources;
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
  StreamController<RecordStop>? _stopStreamCtrl;
  void Function(RecordConfig config)? _configChangedHandler;

  Future<void> dispose() async {
    await stop();

    await _stateStreamCtrl?.close();
    _stateStreamCtrl = null;
    await _stopStreamCtrl?.close();
    _stopStreamCtrl = null;
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

  Future<String?> stop() => _end(delete: false);

  Future<void> cancel() => _end(delete: true);

  Stream<RecordState> onStateChanged() {
    _stateStreamCtrl ??= StreamController.broadcast();
    return _stateStreamCtrl!.stream;
  }

  Stream<RecordStop> onStopped() {
    _stopStreamCtrl ??= StreamController.broadcast();
    return _stopStreamCtrl!.stream;
  }

  void setOnConfigChanged(void Function(RecordConfig config)? handler) {
    _configChangedHandler = handler;
  }

  Future<String?> _end({
    required bool delete,
    RecordStopReason reason = RecordStopReason.stop,
    String? error,
  }) async {
    final path = _path;
    final wasRecording = _state != RecordState.stop;
    // Set before the await, so an end that comes meanwhile reports nothing.
    _state = RecordState.stop;

    _config = null;
    _routeLost = false;
    _routeMonitor.stop();
    await _pipeline.stop();

    _path = null;
    if (delete) _deleteFile(path);

    if (wasRecording) {
      _emitState(RecordState.stop);
      // The state goes first: Dart hears RecordState.stop, then why.
      if (_stopStreamCtrl case final controller? when controller.hasListener) {
        controller.add(
          RecordStop(reason: reason, path: delete ? null : path, error: error),
        );
      }
    }

    return path;
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
          await _end(delete: false, reason: RecordStopReason.routeChange);
      }
    } catch (e) {
      // Nothing awaits the monitor callback, so catch here.
      debugPrint(e.toString());
    }
  }

  Future<void> _onPipelineExited(String error, {required bool capture}) async {
    final config = _config;
    if (config == null) return;

    try {
      // With no source left, the server ends the stream: the route monitor handles that.
      if (capture && await _sourceGone(config)) return;
      // The take may end while pactl runs.
      if (!identical(config, _config)) return;

      await _end(delete: false, reason: RecordStopReason.error, error: error);
    } catch (e) {
      // Nothing awaits the exit callback, so catch here.
      debugPrint(e.toString());
    }
  }

  Future<bool> _sourceGone(RecordConfig config) async {
    try {
      return !_isAvailable(config.device, await listSources());
    } catch (_) {
      // Without pactl there is no route handling either: report the failure.
      return false;
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

    final available = _isAvailable(device, await listSources());
    // The take may end while pactl runs.
    if (!available || !identical(config, _config)) return false;

    final moved = config.copyWith(device: (value: device));
    await _pipeline.restartCapture(moved);
    if (!identical(config, _config)) return false;

    // A pause() during the move stopped the old parecord, not this one.
    if (_state == RecordState.pause && !_routeLost) _pipeline.pause();

    _config = moved;
    if (config.device?.id != device?.id) _configChangedHandler?.call(moved);
    await _watchRoute();

    return true;
  }

  /// Whether [device], or any source when null, is among [sources].
  bool _isAvailable(InputDevice? device, Set<String> sources) {
    return device == null ? sources.isNotEmpty : sources.contains(device.id);
  }

  void _updateState(RecordState state) {
    if (_state == state) return;

    _state = state;
    _emitState(state);
  }

  void _emitState(RecordState state) {
    if (_stateStreamCtrl case final controller? when controller.hasListener) {
      controller.add(state);
    }
  }
}
