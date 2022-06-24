import 'dart:async';

import 'package:record_platform_interface/record_platform_interface.dart';

/// All states of the recorder
enum RecordState { paused, resumed, stopped }

/// Audio recorder API
class Record implements RecordPlatform {
  @override
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
  }) {
    return RecordPlatform.instance.start(
      path: path,
      encoder: encoder,
      bitRate: bitRate,
      samplingRate: samplingRate,
    );
  }

  StreamController<RecordState>? _stateStreamCtrl;
  StreamController<Amplitude>? _amplitudeStreamCtrl;

  @override
  Future<String?> stop() async {
    final result = RecordPlatform.instance.stop();

    if (_stateStreamCtrl?.hasListener ?? false) {
      _stateStreamCtrl?.add(RecordState.stopped);
    }

    return result;
  }

  @override
  Future<void> pause() async {
    await RecordPlatform.instance.pause();

    if (_stateStreamCtrl?.hasListener ?? false) {
      _stateStreamCtrl?.add(RecordState.paused);
    }
  }

  @override
  Future<void> resume() async {
    await RecordPlatform.instance.resume();

    if (_stateStreamCtrl?.hasListener ?? false) {
      _stateStreamCtrl?.add(RecordState.resumed);
    }
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

    while (await shouldUpdate()) {
      await Future.delayed(interval);

      if (_amplitudeStreamCtrl?.hasListener ?? false) {
        _amplitudeStreamCtrl?.add(await getAmplitude());
      }
    }
  }
}
