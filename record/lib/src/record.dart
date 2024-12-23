import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Audio recorder
class AudioRecorder {
  StreamController<Amplitude>? _amplitudeStreamCtrl;

  final _stateStreamCtrl = StreamController<RecordState>.broadcast();
  StreamSubscription? _stateStreamSubscription;

  StreamController<Uint8List>? _recordStreamCtrl;
  StreamSubscription? _recordStreamSubscription;

  Timer? _amplitudeTimer;
  late Duration _amplitudeTimerInterval;
  final _semaphore = _Semaphore();

  // Recorder ID
  final String _recorderId;
  // Flag to create the recorder if needed with `_recorderId`.
  bool? _created;

  AudioRecorder() : _recorderId = _uuid.v4();

  Future<bool> _create() async {
    await RecordPlatform.instance.create(_recorderId);

    final stream = RecordPlatform.instance.onStateChanged(_recorderId);
    _stateStreamSubscription = stream.listen(
      _stateStreamCtrl.add,
      onError: _stateStreamCtrl.addError,
    );

    return true;
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
    await _safeCall(
      () async {
        _created ??= await _create();

        await RecordPlatform.instance.start(_recorderId, config, path: path);
      },
    );

    _startAmplitudeTimer();
  }

  /// Same as [start] with output stream instead of a path.
  ///
  /// When stopping the record, you must rely on stream close event to get
  /// full recorded data.
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    final stream = await _safeCall(
      () async {
        _created ??= await _create();
        await _stopRecordStream();

        return await RecordPlatform.instance.startStream(
          _recorderId,
          config,
        );
      },
    );

    _recordStreamCtrl = StreamController.broadcast();

    _recordStreamSubscription = stream.listen(
      (data) {
        final streamCtrl = _recordStreamCtrl;
        if (streamCtrl == null || streamCtrl.isClosed) return;

        streamCtrl.add(data);
      },
    );

    _startAmplitudeTimer();

    return _recordStreamCtrl!.stream;
  }

  /// Stops recording session and release internal recorder resource.
  ///
  /// Returns the output path if any.
  Future<String?> stop() async {
    return _safeCall(() async {
      _amplitudeTimer?.cancel();

      if (_created == null) return null;

      final path = await RecordPlatform.instance.stop(_recorderId);

      await _stopRecordStream();

      return path;
    });
  }

  /// Stops and discards/deletes the file/blob.
  Future<void> cancel() async {
    return _safeCall(() async {
      _amplitudeTimer?.cancel();

      if (_created == null) return;

      return RecordPlatform.instance.cancel(_recorderId);
    });
  }

  /// Pauses recording session.
  Future<void> pause() async {
    return _safeCall(() async {
      _amplitudeTimer?.cancel();

      if (_created == null) return;

      return RecordPlatform.instance.pause(_recorderId);
    });
  }

  /// Resumes recording session after [pause].
  Future<void> resume() async {
    return _safeCall(() async {
      if (_created == null) return;
      _startAmplitudeTimer();
      return RecordPlatform.instance.resume(_recorderId);
    });
  }

  /// Checks if there's valid recording session.
  /// So if session is paused, this method will still return [true].
  Future<bool> isRecording() async {
    return _safeCall(() async {
      if (_created == null) return false;
      return RecordPlatform.instance.isRecording(_recorderId);
    });
  }

  /// Checks if recording session is paused.
  Future<bool> isPaused() async {
    return _safeCall(() async {
      if (_created == null) return false;
      return RecordPlatform.instance.isPaused(_recorderId);
    });
  }

  /// Checks and requests for audio record permission.
  Future<bool> hasPermission() async {
    return _safeCall(() async {
      _created ??= await _create();
      return RecordPlatform.instance.hasPermission(_recorderId);
    });
  }

  /// Lists capture/input devices available on the platform.
  ///
  /// On web, and in general, you should already have permission before
  /// accessing this method otherwise the list may return an empty list.
  Future<List<InputDevice>> listInputDevices() async {
    return _safeCall(() async {
      _created ??= await _create();
      return RecordPlatform.instance.listInputDevices(_recorderId);
    });
  }

  /// Gets current average & max amplitudes (dBFS)
  /// Always returns zeros on unsupported platforms
  Future<Amplitude> getAmplitude() async {
    return _safeCall(() async {
      _created ??= await _create();
      return RecordPlatform.instance.getAmplitude(_recorderId);
    });
  }

  /// Checks if the given encoder is supported on the current platform.
  Future<bool> isEncoderSupported(AudioEncoder encoder) async {
    return _safeCall(() async {
      _created ??= await _create();
      return RecordPlatform.instance.isEncoderSupported(_recorderId, encoder);
    });
  }

  /// Dispose the recorder
  Future<void> dispose() async {
    return _safeCall(() async {
      _amplitudeTimer?.cancel();
      _amplitudeStreamCtrl?.close();
      _amplitudeStreamCtrl = null;

      _stateStreamSubscription?.cancel();
      _stateStreamCtrl.close();

      if (_created != null) {
        await RecordPlatform.instance.dispose(_recorderId);
      }

      await _stopRecordStream();

      _created = null;
    });
  }

  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  ///
  /// Also, you can retrieve async errors from it by adding [Function? onError].
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
      final amplitude = await getAmplitude();
      _amplitudeStreamCtrl?.add(amplitude);
    }
  }

  void _startAmplitudeTimer() {
    _amplitudeTimer?.cancel();

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
  List<int> convertBytesToInt16(Uint8List bytes, [endian = Endian.little]) {
    final values = <int>[];

    final data = ByteData.view(bytes.buffer);

    for (var i = 0; i < bytes.length; i += 2) {
      int short = data.getInt16(i, endian);
      values.add(short);
    }

    return values;
  }

  Future<T> _safeCall<T>(Future<T> Function() fn) async {
    await _semaphore.acquire();
    try {
      return await fn();
    } finally {
      _semaphore.release();
    }
  }
}

/// A class that represents a semaphore.
class _Semaphore {
  final int maxCount;

  int _counter = 0;
  final _waitQueue = Queue<Completer>();

  // ignore: unused_element
  _Semaphore([this.maxCount = 1]) {
    if (maxCount < 1) {
      throw RangeError.value(maxCount, "maxCount");
    }
  }

  /// Acquires a permit from this semaphore, asynchronously blocking until one
  /// is available.
  Future acquire() {
    var completer = Completer();
    if (_counter + 1 <= maxCount) {
      _counter++;
      completer.complete();
    } else {
      _waitQueue.add(completer);
    }
    return completer.future;
  }

  /// Releases a permit, returning it to the semaphore.
  void release() {
    if (_counter == 0) {
      throw StateError("Unable to release semaphore.");
    }
    _counter--;
    if (_waitQueue.isNotEmpty) {
      _counter++;
      var completer = _waitQueue.removeFirst();
      completer.complete();
    }
  }
}
