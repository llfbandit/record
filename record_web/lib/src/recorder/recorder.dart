import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:record_web/src/mime_types.dart';
import 'package:record_web/src/recorder/delegate/media_recorder_delegate.dart';
import 'package:record_web/src/recorder/delegate/mic_recorder_delegate.dart';
import 'package:record_web/src/recorder/delegate/recorder_delegate.dart';

const kMaxAmplitude = 0.0;
const kMinAmplitude = -160.0;

class Recorder {
  RecorderDelegate? _delegate;
  StreamController<RecordState>? _stateStreamCtrl;
  StreamController<RecordStop>? _stopStreamCtrl;
  void Function(RecordConfig)? _onConfigChanged;
  // cancel() deletes the take, so its stop has no path.
  bool _cancelling = false;

  Future<bool> _requestPermission() async {
    final mediaDevices = web.window.navigator.mediaDevices;

    try {
      final constraints = web.MediaStreamConstraints(audio: {true}.toJSBox);
      final ms = await mediaDevices.getUserMedia(constraints).toDart;

      // Clean-up
      final tracks = ms.getAudioTracks().toDart;
      for (var track in tracks) {
        track.stop();
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission({bool request = true}) async {
    try {
      final permissions = web.window.navigator.permissions;
      final permissionStatus = await permissions
          .query(_PermissionDescriptor(name: 'microphone'))
          .toDart;

      final isGranted = permissionStatus.state == 'granted';
      if (!isGranted && request) return await _requestPermission();

      return isGranted;
    } catch (_) {
      if (request) return _requestPermission();
      return false;
    }
  }

  Future<List<InputDevice>> listInputDevices() async {
    try {
      await _requestPermission();

      var deviceInfos = await web.window.navigator.mediaDevices
          .enumerateDevices()
          .toDart;

      var inputs = deviceInfos.toDart
          .where((d) => d.kind == 'audioinput')
          .toList();

      return inputs
          .map((d) => InputDevice(id: d.deviceId, label: d.label))
          .toList();
    } catch (error) {
      debugPrint(error.toString());
      return [];
    }
  }

  Future<bool> isEncoderSupported(AudioEncoder encoder) {
    switch (encoder) {
      case AudioEncoder.wav:
      case AudioEncoder.pcm16bits:
        return Future.value(true);
      default:
        final type = getSupportedMimeType(encoder);

        return Future.value(type != null ? true : false);
    }
  }

  Future<void> dispose() async {
    await _stateStreamCtrl?.close();
    await _stopStreamCtrl?.close();
    return _delegate?.dispose();
  }

  Future<Amplitude> getAmplitude() async {
    final delegate = _delegate;

    if (delegate == null) {
      return Amplitude(current: -160.0, max: -160.0);
    }

    return delegate.getAmplitude();
  }

  Future<bool> isPaused() async {
    final delegate = _delegate;

    if (delegate == null) {
      return false;
    }

    return delegate.isPaused();
  }

  Future<bool> isRecording() async {
    final delegate = _delegate;

    if (delegate == null) {
      return false;
    }

    return delegate.isRecording();
  }

  Future<void> pause() async {
    final delegate = _delegate;

    if (delegate == null) {
      return;
    }

    return delegate.pause();
  }

  Future<void> resume() async {
    final delegate = _delegate;

    if (delegate == null) {
      return;
    }

    return delegate.resume();
  }

  Future<void> start(RecordConfig config, {required String path}) async {
    switch (config.encoder) {
      case AudioEncoder.wav:
      case AudioEncoder.pcm16bits:
        await _endTake();
        _delegate = MicRecorderDelegate(
          onStateChanged: _updateState,
          onStopped: _onStopped,
          onConfigChanged: _onConfigChanged,
        );
        return _delegate!.start(config, path: path);
      default:
        await _endTake();

        final supported = await isEncoderSupported(config.encoder);
        if (!supported) {
          throw Exception('Encoder ${config.encoder} not supported.');
        }

        _delegate = MediaRecorderDelegate(
          onStateChanged: _updateState,
          onStopped: _onStopped,
          onConfigChanged: _onConfigChanged,
        );
        return _delegate!.start(config, path: path);
    }
  }

  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    switch (config.encoder) {
      case AudioEncoder.pcm16bits:
        await _endTake();
        _delegate = MicRecorderDelegate(
          onStateChanged: _updateState,
          onStopped: _onStopped,
          onConfigChanged: _onConfigChanged,
        );
        return _delegate!.startStream(config);
      default:
        throw Exception('Stream not supported.');
    }
  }

  Future<String?> stop() async {
    final delegate = _delegate;

    if (delegate == null) {
      return null;
    }

    return delegate.stop();
  }

  Future<void> cancel() async {
    _cancelling = true;
    final String? url;
    try {
      url = await stop();
    } finally {
      _cancelling = false;
    }

    if (url != null) {
      web.URL.revokeObjectURL(url);
    }
  }

  void setOnConfigChanged(void Function(RecordConfig)? handler) {
    _onConfigChanged = handler;
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

  Stream<RecordStop> onStopped() {
    _stopStreamCtrl ??= StreamController(
      onCancel: () {
        _stopStreamCtrl?.close();
        _stopStreamCtrl = null;
      },
    );

    return _stopStreamCtrl!.stream;
  }

  // The state goes first: Dart hears RecordState.stop, then why.
  void _onStopped(RecordStop stop) {
    _updateState(RecordState.stop);

    final ctrl = _stopStreamCtrl;
    if (ctrl == null || !ctrl.hasListener || ctrl.isClosed) return;
    ctrl.add(_cancelling ? RecordStop(reason: stop.reason) : stop);
  }

  // A new take ends the running one first, so the app hears its stop.
  Future<void> _endTake() async {
    final delegate = _delegate;
    _delegate = null;
    await delegate?.stop();
    await delegate?.dispose();
  }

  void _updateState(RecordState state) {
    final ctrl = _stateStreamCtrl;
    if (ctrl == null) return;

    if (ctrl.hasListener && !ctrl.isClosed) {
      ctrl.add(state);
    }
  }
}

// copied from https://github.com/dart-lang/web/commit/7604578eb538c471d438608673c037121d95dba5#diff-6f4c7956b6e25b547b16fc561e54d5e7d520d2c79a59ace4438c60913cc2b1a2L35-L40
extension type _PermissionDescriptor._(JSObject _) implements JSObject {
  external factory _PermissionDescriptor({required String name});

  external set name(String value);
  external String get name;
}
