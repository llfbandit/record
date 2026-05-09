part of '../record.dart';

typedef _IsRecording = Future<bool> Function();
typedef _GetAmplitude = Future<Amplitude> Function();

/// Methods for amplitude monitoring.
mixin _AmplitudeMixin {
  Timer? _amplitudeTimer;
  StreamController<Amplitude>? _amplitudeStreamCtrl;
  Duration _amplitudeTimerInterval = Duration(milliseconds: 300);

  /// Requests for amplitude at given [interval].
  Stream<Amplitude> _onAmplitudeChanged(
    Duration interval,
    _IsRecording isRecording,
    _GetAmplitude getAmplitude,
  ) {
    if (_amplitudeStreamCtrl case final ctrl?) {
      return ctrl.stream;
    }

    _amplitudeStreamCtrl = StreamController<Amplitude>.broadcast();

    _amplitudeTimerInterval = interval;
    _startAmplitudeMonitoring(isRecording, getAmplitude);

    return _amplitudeStreamCtrl!.stream;
  }

  /// Starts or restarts the amplitude monitoring timer.
  void _startAmplitudeMonitoring(
    _IsRecording isRecording,
    _GetAmplitude getAmplitude,
  ) {
    _amplitudeTimer?.cancel();

    if (_amplitudeStreamCtrl == null) return;

    _amplitudeTimer = Timer.periodic(
      _amplitudeTimerInterval,
      (timer) => _updateAmplitudeAtInterval(isRecording, getAmplitude),
    );
  }

  /// Stops the amplitude monitoring timer.
  void _stopAmplitudeMonitoring() {
    _amplitudeTimer?.cancel();
  }

  /// Disposes amplitude-related resources.
  Future<void> _disposeAmplitude() async {
    _amplitudeTimer?.cancel();
    await _amplitudeStreamCtrl?.close();
    _amplitudeStreamCtrl = null;
  }

  Future<void> _updateAmplitudeAtInterval(
    _IsRecording isRecording,
    _GetAmplitude getAmplitude,
  ) async {
    Future<bool> shouldUpdate() async {
      var result = _amplitudeStreamCtrl != null;
      result &= !(_amplitudeStreamCtrl?.isClosed ?? true);
      result &= _amplitudeStreamCtrl?.hasListener ?? false;
      result &= _amplitudeTimer?.isActive ?? false;

      return result && await isRecording();
    }

    if (await shouldUpdate()) {
      final amplitude = await getAmplitude();
      _amplitudeStreamCtrl?.add(amplitude);
    }
  }
}
