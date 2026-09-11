import 'dart:async';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

import 'util/semaphore.dart';
import 'util/uuid_v4.dart';

part 'part/record_amplitude.dart';
part 'part/record_convert.dart';
part 'part/record_state.dart';
part 'part/record_stream.dart';

typedef _SafeCall<T> = Future<T> Function(Future<T> Function() fn);

/// Audio recorder for capturing audio from input devices.
///
class AudioRecorder with _AmplitudeMixin, _StateMixin, _StreamMixin {
  final String _recorderId;

  // Semaphore to ensure sequential calls to platform.
  final _semaphore = Semaphore();

  // A future to store potential error during initialization.
  late final Future<void> _createFuture;

  Stream<RecordState>? _recordStateStream;

  RecordPlatform get _platform => RecordPlatform.instance;

  /// Creates a new audio recorder.
  AudioRecorder() : _recorderId = UuidV4.generate() {
    _createFuture = () async {
      await _semaphore.acquire();
      try {
        await _platform.create(_recorderId);
      } finally {
        _semaphore.release();
      }
    }();
  }

  /// Starts new recording session.
  ///
  /// [path]: The output path file. Required on all IO platforms.
  /// On `web`: This parameter is ignored.
  ///
  /// Output path can be retrieves when [stop] method is called.
  Future<void> start(RecordConfig config, {required String path}) async {
    _initStateStream();

    await _safeCall(() => _platform.start(_recorderId, config, path: path));
  }

  /// Starts stream recording and returns the stream.
  ///
  /// When stopping the record, you must rely on stream close event to get
  /// full recorded data.
  Future<Stream<Uint8List>> startStream(RecordConfig config) {
    _initStateStream();

    return _safeCall(() async {
      await _stopRecordStream();

      final stream = await _platform.startStream(_recorderId, config);
      return _startRecordStream(stream);
    });
  }

  /// Stops recording session and release internal recorder resource.
  ///
  /// Returns the output path if any.
  ///
  /// On web, this is a blob URL that keeps the recording in memory
  /// until you call `URL.revokeObjectURL` on it.
  Future<String?> stop() {
    return _safeCall(() async {
      final path = await _platform.stop(_recorderId);

      await _stopRecordStream();

      return path;
    });
  }

  /// Stops and discards/deletes the file/blob.
  Future<void> cancel() {
    return _safeCall(() async {
      await _platform.cancel(_recorderId);

      return _stopRecordStream();
    });
  }

  /// Pauses recording session.
  Future<void> pause() {
    return _safeCall(() {
      return _platform.pause(_recorderId);
    });
  }

  /// Resumes recording session after [pause].
  Future<void> resume() {
    return _safeCall(() {
      return _platform.resume(_recorderId);
    });
  }

  /// Sets a callback invoked when the platform adjusted the requested [RecordConfig]
  /// to match hardware or codec constraints.
  ///
  /// Only called when at least one field differs from what was requested.
  /// Pass [null] to unregister.
  Future<void> setOnConfigChanged(
    void Function(RecordConfig config)? callback,
  ) {
    return _safeCall(() async {
      _platform.setOnConfigChanged(_recorderId, callback);
    });
  }

  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  ///
  /// Also, you can retrieve async errors from it by adding [Function? onError] callback to the subscription.
  Stream<RecordState> onStateChanged() =>
      _recordStateStream ?? _initStateStream();

  /// Requests for amplitude at given [interval].
  Stream<Amplitude> onAmplitudeChanged(Duration interval) {
    return _onAmplitudeChanged(interval, isRecording, getAmplitude);
  }

  /// Checks if there's valid recording session.
  /// So if session is paused, this method will still return [true].
  Future<bool> isRecording() {
    return _safeCall(() => _platform.isRecording(_recorderId));
  }

  /// Checks if recording session is paused.
  Future<bool> isPaused() {
    return _safeCall(() => _platform.isPaused(_recorderId));
  }

  /// Checks and optionally requests for audio record permission.
  ///
  /// The [request] parameter controls whether to request permission if not
  /// already granted. Defaults to `true`.
  Future<bool> hasPermission({bool request = true}) {
    return _safeCall(
      () => _platform.hasPermission(_recorderId, request: request),
    );
  }

  /// Lists capture/input devices available on the platform.
  ///
  /// On web, and in general, you should already have permission before
  /// accessing this method otherwise the list may return an empty list.
  Future<List<InputDevice>> listInputDevices() {
    return _safeCall(() => _platform.listInputDevices(_recorderId));
  }

  /// Gets current average & max amplitudes (dBFS)
  /// Always returns zeros on unsupported platforms
  Future<Amplitude> getAmplitude() {
    return _safeCall(() => _platform.getAmplitude(_recorderId));
  }

  /// Checks if the given encoder is supported on the current platform.
  Future<bool> isEncoderSupported(AudioEncoder encoder) {
    return _safeCall(() => _platform.isEncoderSupported(_recorderId, encoder));
  }

  /// Disposes the recorder.
  Future<void> dispose() {
    return _safeCall(() async {
      await _disposeAmplitude();
      await _disposeState();
      await _stopRecordStream();
      await _platform.dispose(_recorderId);
    });
  }

  /// iOS platform specific methods.
  ///
  /// Returns [null] when not on iOS platform.
  RecordIos? get ios {
    final inner = _platform.getIos(_recorderId);
    if (inner == null) return null;

    return _RecordIosSafeWrapper(inner, _safeCall);
  }

  /// Initialize state stream.
  /// Must be called outside of `_safeCall` to avoid deadlock.
  Stream<RecordState> _initStateStream() {
    _recordStateStream ??= _onStateChanged(
      _platform,
      _recorderId,
      _handleAmplitudeRequesting,
      _semaphore,
    );

    return _recordStateStream!;
  }

  void _handleAmplitudeRequesting(RecordState state) {
    switch (state) {
      case RecordState.pause:
      case RecordState.stop:
        _stopAmplitudeMonitoring();
      case RecordState.record:
        _startAmplitudeMonitoring(isRecording, getAmplitude);
    }
  }

  /// Safe call to [fn] with semaphore permit.
  Future<T> _safeCall<T>(Future<T> Function() fn) async {
    await _createFuture;
    await _semaphore.acquire();
    try {
      return await fn();
    } finally {
      _semaphore.release();
    }
  }
}

/// Wrapper around semaphore for safe calls.
class _RecordIosSafeWrapper implements RecordIos {
  final RecordIos inner;
  final _SafeCall<void> safeCall;

  _RecordIosSafeWrapper(this.inner, this.safeCall);

  @override
  Future<void> manageAudioSession(bool manage) {
    return safeCall(() => inner.manageAudioSession(manage));
  }

  @override
  Future<void> setAudioSessionActive(bool active) {
    return safeCall(() => inner.setAudioSessionActive(active));
  }

  @override
  Future<void> setAudioSessionCategory({
    IosAudioCategory category = IosAudioCategory.playAndRecord,
    List<IosAudioCategoryOptions> options = const [
      IosAudioCategoryOptions.duckOthers,
      IosAudioCategoryOptions.defaultToSpeaker,
      IosAudioCategoryOptions.allowBluetooth,
      IosAudioCategoryOptions.allowBluetoothA2DP,
    ],
  }) {
    return safeCall(() {
      return inner.setAudioSessionCategory(
        category: category,
        options: options,
      );
    });
  }
}
