import 'dart:async';

import 'package:record_platform_interface/record_platform_interface.dart';

/// All states of the recorder
enum RecordState { pause, record, stop }

/// Audio recorder API
class Record implements RecordPlatform {
  @override
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
  }) async {
    await RecordPlatform.instance.start(
      path: path,
      encoder: encoder,
      bitRate: bitRate,
      samplingRate: samplingRate,
    );

    return _sendStateEvent(RecordState.record);
  }

  StreamController<RecordState>? _stateStreamCtrl;
  StreamController<Amplitude>? _amplitudeStreamCtrl;

  @override
  Future<String?> stop() async {
    final result = await RecordPlatform.instance.stop();

    await _sendStateEvent(RecordState.stop);

    return result;
  }

  @override
  Future<void> pause() async {
    await RecordPlatform.instance.pause();

    return _sendStateEvent(RecordState.pause);
  }

  @override
  Future<void> resume() async {
    await RecordPlatform.instance.resume();

    return _sendStateEvent(RecordState.record);
  }

  @override
  Future<bool> isRecording() {
    return RecordPlatform.instance.isRecording();
  }

  @override
  Future<bool> isPaused() {
    return RecordPlatform.instance.isPaused();
  }

  @override
  Future<bool> hasPermission() {
    return RecordPlatform.instance.hasPermission();
  }

  @override
  Future<void> dispose() {
    _stateStreamCtrl?.close();
    _amplitudeStreamCtrl?.close();

    return RecordPlatform.instance.dispose();
  }

  @override
  Future<Amplitude> getAmplitude() {
    return RecordPlatform.instance.getAmplitude();
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) {
    return RecordPlatform.instance.isEncoderSupported(encoder);
  }

  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  Stream<RecordState> onStateChanged() {
    _stateStreamCtrl ??= StreamController(
      onCancel: () {
        _stateStreamCtrl?.close();
        _stateStreamCtrl = null;
      },
    );

    return _stateStreamCtrl!.stream;
  }

  /// Listen to amplitude.
  Stream<Amplitude> onAmplitudeChanged(Duration interval) {
    _amplitudeStreamCtrl ??= StreamController(
      onCancel: () {
        _amplitudeStreamCtrl?.close();
        _amplitudeStreamCtrl = null;
      },
      onListen: () => _updateAmplitudeAtInterval(interval),
    );

    return _amplitudeStreamCtrl!.stream;
  }

  Future<void> _updateAmplitudeAtInterval(Duration interval) async {
    Future<bool> shouldUpdate() {
      var result = _amplitudeStreamCtrl != null;
      result &= !(_amplitudeStreamCtrl?.isClosed ?? true);
      result &= _amplitudeStreamCtrl?.hasListener ?? false;

      return result ? isRecording() : Future.value(false);
    }

    while (await Future.delayed(interval)) {
      if (!await shouldUpdate()) break;
      _amplitudeStreamCtrl?.add(await getAmplitude());
    }
  }

  Future<void> _sendStateEvent(RecordState state) async {
    if (_stateStreamCtrl?.hasListener ?? false) {
      switch (state) {
        case RecordState.record:
          final isRecording = await RecordPlatform.instance.isRecording();
          if (isRecording) _stateStreamCtrl?.add(state);
          break;
        case RecordState.pause:
          final isPaused = await RecordPlatform.instance.isPaused();
          if (isPaused) _stateStreamCtrl?.add(state);
          break;
        case RecordState.stop:
          final isRecording = await RecordPlatform.instance.isRecording();
          if (!isRecording) _stateStreamCtrl?.add(state);
          break;
      }
    }
  }
}
