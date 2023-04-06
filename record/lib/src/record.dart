import 'dart:async';

import 'package:record_platform_interface/record_platform_interface.dart';

/// Audio recorder API
class AudioRecorder implements RecordPlatform {
  StreamController<Amplitude>? _amplitudeStreamCtrl;

  Timer? _amplitudeTimer;

  @override
  Future<void> start(RecordConfig config, {required String path}) {
    return RecordPlatform.instance.start(config, path: path);
  }

  @override
  Future<Stream<List<int>>> startStream(RecordConfig config) {
    return RecordPlatform.instance.startStream(config);
  }

  @override
  Future<String?> stop() {
    return RecordPlatform.instance.stop();
  }

  @override
  Future<void> pause() {
    return RecordPlatform.instance.pause();
  }

  @override
  Future<void> resume() {
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
}
