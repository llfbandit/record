import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// Audio recorder API
class Record implements RecordPlatform {
  StreamController<Amplitude>? _amplitudeStreamCtrl;
  Timer? _amplitudeTimer;

  @override
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
    int numChannels = 2,
    InputDevice? device,
  }) {
    _log('Start recording');
    return RecordPlatform.instance.start(
      path: path,
      encoder: encoder,
      bitRate: bitRate,
      samplingRate: samplingRate,
      numChannels: numChannels,
      device: device,
    );
  }

  @override
  Future<String?> stop() {
    _log('Stop recording');
    return RecordPlatform.instance.stop();
  }

  @override
  Future<void> pause() {
    _log('Pause recording');
    return RecordPlatform.instance.pause();
  }

  @override
  Future<void> resume() {
    _log('Resume recording');
    return RecordPlatform.instance.resume();
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
  Future<List<InputDevice>> listInputDevices() {
    return RecordPlatform.instance.listInputDevices();
  }

  @override
  Future<Amplitude> getAmplitude() {
    return RecordPlatform.instance.getAmplitude();
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) {
    return RecordPlatform.instance.isEncoderSupported(encoder);
  }

  @override
  Future<void> dispose() async {
    _amplitudeTimer?.cancel();
    await _amplitudeStreamCtrl?.close();
    return RecordPlatform.instance.dispose();
  }

  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  @override
  Stream<RecordState> onStateChanged() {
    return RecordPlatform.instance.onStateChanged();
  }

  /// Listen to amplitude.
  Stream<Amplitude> onAmplitudeChanged(Duration interval) {
    _amplitudeStreamCtrl ??= StreamController(
      onCancel: () {
        _amplitudeTimer?.cancel();
        _amplitudeStreamCtrl?.close();
        _amplitudeStreamCtrl = null;
      },
    );

    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(
      interval,
      (timer) => _updateAmplitudeAtInterval(),
    );

    return _amplitudeStreamCtrl!.stream;
  }

  Future<void> _updateAmplitudeAtInterval() async {
    Future<bool> shouldUpdate() async {
      var result = _amplitudeStreamCtrl != null;
      result &= !(_amplitudeStreamCtrl?.isClosed ?? true);
      result &= _amplitudeStreamCtrl?.hasListener ?? false;
      result &= await isRecording() && !(await isPaused());

      return result;
    }

    if (await shouldUpdate()) {
      _amplitudeStreamCtrl?.add(await getAmplitude());
    }
  }

  void _log(String msg) {
    if (kDebugMode) print(msg);
  }
}
