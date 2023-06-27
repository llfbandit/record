import 'dart:async';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Audio recorder
class AudioRecorder {
  StreamController<Amplitude>? _amplitudeStreamCtrl;

  final _stateStreamCtrl = StreamController<RecordState>.broadcast();
  late final StreamSubscription _stateStreamSubscription;

  StreamController<Uint8List>? _recordStreamCtrl;
  StreamSubscription? _recordStreamSubscription;

  Timer? _amplitudeTimer;
  late Duration _amplitudeTimerInterval;

  final String _recorderId;

  /// Completer to wait until the native player and its event stream are
  /// created.
  final _createCompleter = Completer<void>();

  AudioRecorder() : _recorderId = _uuid.v4() {
    _create();
  }

  Future<void> _create() async {
    try {
      await RecordPlatform.instance.create(_recorderId);

      _stateStreamSubscription =
          RecordPlatform.instance.onStateChanged(_recorderId).listen(
                _stateStreamCtrl.add,
                onError: _stateStreamCtrl.addError,
              );

      _createCompleter.complete();
    } catch (e, stackTrace) {
      _createCompleter.completeError(e, stackTrace);
    }
  }

  /// Starts new recording session.
  ///
  /// [path]: The output path file. Required on all IO platforms.
  /// On `web`: This parameter is ignored.
  ///
  /// Output path can be retrieves when [stop] method is called.
  Future<void> start(
    RecordConfig config, {
    required String path,
  }) async {
    await _createCompleter.future;
    return RecordPlatform.instance.start(_recorderId, config, path: path);
  }

  /// Same as [start] with output stream instead of a path.
  ///
  /// When stopping the record, you must rely on stream close event to get
  /// full recorded data.
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    await _createCompleter.future;
    await _stopRecordStream();

    final stream = await RecordPlatform.instance.startStream(
      _recorderId,
      config,
    );

    _recordStreamCtrl = StreamController.broadcast();

    _recordStreamSubscription = stream.listen(
      (data) {
        final streamCtrl = _recordStreamCtrl;
        if (streamCtrl == null || streamCtrl.isClosed) return;

        streamCtrl.add(data);
      },
    );

    return _recordStreamCtrl!.stream;
  }

  /// Stops recording session and release internal recorder resource.
  ///
  /// Returns the output path if any.
  Future<String?> stop() async {
    await _createCompleter.future;
    _amplitudeTimer?.cancel();

    final path = await RecordPlatform.instance.stop(_recorderId);

    await _stopRecordStream();

    return path;
  }

  /// Pauses recording session.
  Future<void> pause() async {
    await _createCompleter.future;
    _amplitudeTimer?.cancel();
    return RecordPlatform.instance.pause(_recorderId);
  }

  /// Resumes recording session after [pause].
  Future<void> resume() async {
    await _createCompleter.future;
    _startAmplitudeTimer();
    return RecordPlatform.instance.resume(_recorderId);
  }

  /// Checks if there's valid recording session.
  /// So if session is paused, this method will still return [true].
  Future<bool> isRecording() async {
    await _createCompleter.future;
    return RecordPlatform.instance.isRecording(_recorderId);
  }

  /// Checks if recording session is paused.
  Future<bool> isPaused() async {
    await _createCompleter.future;
    return RecordPlatform.instance.isPaused(_recorderId);
  }

  /// Checks and requests for audio record permission.
  Future<bool> hasPermission() async {
    await _createCompleter.future;
    return RecordPlatform.instance.hasPermission(_recorderId);
  }

  /// Lists capture/input devices available on the platform.
  ///
  /// On Android and iOS, an empty list will be returned.
  ///
  /// On web, and in general, you should already have permission before
  /// accessing this method otherwise the list may return an empty list.
  Future<List<InputDevice>> listInputDevices() async {
    await _createCompleter.future;
    return RecordPlatform.instance.listInputDevices(_recorderId);
  }

  /// Gets current average & max amplitudes (dBFS)
  /// Always returns zeros on unsupported platforms
  Future<Amplitude> getAmplitude() async {
    await _createCompleter.future;
    return RecordPlatform.instance.getAmplitude(_recorderId);
  }

  /// Checks if the given encoder is supported on the current platform.
  Future<bool> isEncoderSupported(AudioEncoder encoder) async {
    await _createCompleter.future;
    return RecordPlatform.instance.isEncoderSupported(_recorderId, encoder);
  }

  /// Dispose the recorder
  Future<void> dispose() async {
    _amplitudeStreamCtrl?.close();
    _amplitudeTimer?.cancel();
    _stateStreamSubscription.cancel();

    await RecordPlatform.instance.dispose(_recorderId);

    await _stopRecordStream();
  }

  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  Stream<RecordState> onStateChanged() => _stateStreamCtrl.stream;

  /// Request for amplitude at given [interval].
  Stream<Amplitude> onAmplitudeChanged(Duration interval) {
    _amplitudeStreamCtrl ??= StreamController(
      onCancel: () {
        _amplitudeTimer?.cancel();
        _amplitudeStreamCtrl?.close();
        _amplitudeStreamCtrl = null;
      },
    );

    _amplitudeTimerInterval = interval;

    _amplitudeTimer?.cancel();
    _startAmplitudeTimer();

    return _amplitudeStreamCtrl!.stream;
  }

  Future<void> _updateAmplitudeAtInterval() async {
    Future<bool> shouldUpdate() async {
      var result = _amplitudeStreamCtrl != null;
      result &= !(_amplitudeStreamCtrl?.isClosed ?? true);
      result &= _amplitudeStreamCtrl?.hasListener ?? false;
      result &= _amplitudeTimer?.isActive ?? false;

      return result && await isRecording();
    }

    if (await shouldUpdate()) {
      _amplitudeStreamCtrl?.add(await getAmplitude());
    }
  }

  void _startAmplitudeTimer() {
    if (_amplitudeStreamCtrl == null) return;

    _amplitudeTimer = Timer.periodic(
      _amplitudeTimerInterval,
      (timer) => _updateAmplitudeAtInterval(),
    );
  }

  Future<void> _stopRecordStream() async {
    await _recordStreamSubscription?.cancel();
    await _recordStreamCtrl?.close();
    _recordStreamCtrl = null;
  }

  /// Utility method to get PCM data as signed 16 bits integers.
  List<int> convertBytesToInt16(Uint8List bytes) {
    final values = <int>[];

    final data = ByteData.view(bytes.buffer);

    for (var i = 0; i < bytes.length; i += 2) {
      int short = data.getInt16(i, Endian.host);
      values.add(short);
    }

    return values;
  }
}
