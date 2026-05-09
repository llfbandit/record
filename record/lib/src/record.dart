import 'dart:async';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

import 'util/semaphore.dart';
import 'util/uuid_v4.dart';

part 'part/record_amplitude.dart';
part 'part/record_convert.dart';
part 'part/record_state.dart';
part 'part/record_stream.dart';

// Global semaphore to ensure sequential calls to platform.
final _semaphore = Semaphore();

/// Audio recorder for capturing audio from input devices.
///
class AudioRecorder with _AmplitudeMixin, _StateMixin, _StreamMixin {
  final String _recorderId;

  RecordPlatform get _platform => RecordPlatform.instance;

  /// Creates a new audio recorder.
  AudioRecorder() : _recorderId = UuidV4.generate() {
    _semaphore.acquire();

    _platform.create(_recorderId).whenComplete(() => _semaphore.release());
  }

  /// Starts new recording session.
  ///
  /// [path]: The output path file. Required on all IO platforms.
  /// On `web`: This parameter is ignored.
  ///
  /// Output path can be retrieves when [stop] method is called.
  Future<void> start(RecordConfig config, {required String path}) async {
    await _safeCall(
      () => _platform.start(_recorderId, config, path: path),
    );

    _startAmplitudeMonitoring(isRecording, getAmplitude);
  }

  /// Starts stream recording and returns the stream.
  ///
  /// When stopping the record, you must rely on stream close event to get
  /// full recorded data.
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    final stream = await _safeCall(
      () async {
        await _stopRecordStream();

        return _platform.startStream(_recorderId, config);
      },
    );

    _startAmplitudeMonitoring(isRecording, getAmplitude);

    return _startRecordStream(stream);
  }

  /// Stops recording session and release internal recorder resource.
  ///
  /// Returns the output path if any.
  Future<String?> stop() {
    return _safeCall(() async {
      _stopAmplitudeMonitoring();

      final path = await _platform.stop(_recorderId);

      await _stopRecordStream();

      return path;
    });
  }

  /// Stops and discards/deletes the file/blob.
  Future<void> cancel() {
    return _safeCall(() async {
      _stopAmplitudeMonitoring();

      await _platform.cancel(_recorderId);

      return _stopRecordStream();
    });
  }

  /// Pauses recording session.
  Future<void> pause() {
    return _safeCall(() {
      _stopAmplitudeMonitoring();

      return _platform.pause(_recorderId);
    });
  }

  /// Resumes recording session after [pause].
  Future<void> resume() {
    return _safeCall(() {
      _startAmplitudeMonitoring(isRecording, getAmplitude);

      return _platform.resume(_recorderId);
    });
  }

  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  ///
  /// Also, you can retrieve async errors from it by adding [Function? onError] callback to the subscription.
  Stream<RecordState> onStateChanged() {
    return _onStateChanged(_platform, _recorderId);
  }

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
  RecordIos? get ios => _platform.getIos(_recorderId);

  /// Safe call to [fn] with semaphore permit.
  Future<T> _safeCall<T>(Future<T> Function() fn) async {
    await _semaphore.acquire();
    try {
      return await fn();
    } finally {
      _semaphore.release();
    }
  }
}
