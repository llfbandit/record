import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:record_platform_interface/record_platform_interface.dart';

import 'src/amplitude_tracker.dart';
import 'src/codec_caps.dart';
import 'src/pactl_devices.dart';
import 'src/process_args.dart';

const _parecordBin = 'parecord';
const _ffmpegBin = 'ffmpeg';

class RecordLinux extends RecordPlatform {
  RecordLinux()
    : _parecordExecutable = _parecordBin,
      _ffmpegExecutable = _ffmpegBin;

  @visibleForTesting
  RecordLinux.withExecutables({
    required String parecordBin,
    required String ffmpegBin,
  }) : _parecordExecutable = parecordBin,
       _ffmpegExecutable = ffmpegBin;

  static void registerWith() {
    RecordPlatform.instance = RecordLinux();
  }

  final String _parecordExecutable;
  final String _ffmpegExecutable;

  RecordState _state = RecordState.stop;
  String? _path;
  StreamController<RecordState>? _stateStreamCtrl;
  Process? _parecordProcess;
  Process? _ffmpegProcess;
  StreamController<List<int>>? _inputPcmController;
  Future<void>? _ffmpegPipeDone;
  final _amplitude = AmplitudeTracker();
  void Function(RecordConfig config)? _configChangedHandler;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {
    await stop(recorderId);

    await _stateStreamCtrl?.close();
    _stateStreamCtrl = null;
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) {
    return Future.value(_amplitude.amplitude);
  }

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) {
    return Future.value(true);
  }

  @override
  Future<bool> isEncoderSupported(String recorderId, AudioEncoder encoder) {
    return Future.value(supportsEncoder(encoder));
  }

  @override
  Future<bool> isPaused(String recorderId) {
    return Future.value(_state == RecordState.pause);
  }

  @override
  Future<bool> isRecording(String recorderId) {
    return Future.value(_state == RecordState.record);
  }

  @override
  Future<void> pause(String recorderId) async {
    if (_state == RecordState.record) {
      _parecordProcess?.kill(ProcessSignal.sigstop);
      _updateState(RecordState.pause);
    }
  }

  @override
  Future<void> resume(String recorderId) async {
    if (_state == RecordState.pause) {
      _parecordProcess?.kill(ProcessSignal.sigcont);
      _updateState(RecordState.record);
    }
  }

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    await stop(recorderId);

    _supportedOrThrow(config);

    _deleteFile(path);

    final adjustedConfig = _adjustConfig(config);

    // Step 1: Use parecord to capture raw PCM audio from the microphone
    // We always capture raw PCM (not encoded) so we can calculate amplitude
    final args = parecordArgs(adjustedConfig, path: null, canEncode: false);
    _parecordProcess = await Process.start(_parecordExecutable, args);
    _drain(_parecordProcess!.stderr);

    // Step 2: Pipe the raw PCM through amplitude monitoring to ffmpeg for encoding
    // parecord (capture) -> amplitude calculation -> ffmpeg (encode to file)
    await _startFfmpegWithAmplitudeMonitoring(
      adjustedConfig,
      _parecordProcess!,
      path,
    );

    _path = path;
    _updateState(RecordState.record);
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    await stop(recorderId);

    final adjustedConfig = _adjustConfig(config);

    final args = parecordArgs(adjustedConfig);
    _parecordProcess = await Process.start(_parecordExecutable, args);
    _drain(_parecordProcess!.stderr);

    _updateState(RecordState.record);

    return _parecordProcess!.stdout.map((list) {
      final data = (list is Uint8List) ? list : Uint8List.fromList(list);
      // Calculate amplitude from PCM data
      _amplitude.update(data);
      return data;
    });
  }

  @override
  Future<String?> stop(String recorderId) async {
    final path = _path;

    // Close amplitude stream controller
    await _inputPcmController?.close();
    _inputPcmController = null;

    // Kill parecord first
    _parecordProcess?.kill();
    _parecordProcess = null;

    // Wait for the pipe to flush and close ffmpeg stdin
    if (_ffmpegProcess case final process?) {
      try {
        await _ffmpegPipeDone;
      } catch (_) {
        // ffmpeg may have exited early (broken pipe)
      }
      _ffmpegPipeDone = null;
      await process.exitCode;
      _ffmpegProcess = null;
    }

    _path = null;

    _amplitude.reset();

    _updateState(RecordState.stop);

    return path;
  }

  @override
  Future<void> cancel(String recorderId) async {
    final path = await stop(recorderId);

    _deleteFile(path);
  }

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) {
    return listPactlInputDevices();
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) {
    _stateStreamCtrl ??= StreamController.broadcast();
    return _stateStreamCtrl!.stream;
  }

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {
    _configChangedHandler = handler;
  }

  void _deleteFile(String? path) {
    if (path == null) return;

    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  void _supportedOrThrow(RecordConfig config) {
    if (!supportsEncoder(config.encoder)) {
      throw Exception('${config.encoder} is not supported.');
    }
  }

  RecordConfig _adjustConfig(RecordConfig config) {
    final adjusted = adjustConfig(config);

    if (!identical(adjusted, config)) _configChangedHandler?.call(adjusted);

    return adjusted;
  }

  /// Consumes and discards a child process output stream so the process is
  /// never blocked on a full pipe.
  void _drain(Stream<List<int>> output) {
    output.listen((_) {}, onError: (_) {}, cancelOnError: true);
  }

  void _updateState(RecordState state) {
    if (_state == state) return;

    _state = state;

    if (_stateStreamCtrl case final controller? when controller.hasListener) {
      controller.add(state);
    }
  }

  /// Sets up ffmpeg to encode audio while monitoring amplitude.
  ///
  /// Audio flow: parecord (capture) -> amplitude calculation -> ffmpeg (encode)
  /// - parecord: Captures raw PCM audio from the microphone
  /// - amplitude calculation: Analyzes PCM samples for VU meter (doesn't modify audio)
  /// - ffmpeg: Encodes the PCM data to the desired format (AAC, WAV, FLAC, etc.)
  Future<void> _startFfmpegWithAmplitudeMonitoring(
    RecordConfig config,
    Process parecordProc,
    String path,
  ) async {
    final ffmpegArgs = [
      '-f',
      's16le',
      '-ar',
      config.sampleRate.toString(),
      '-ac',
      '${config.numChannels}',
      '-i',
      '-',
      ...ffmpegEncoderArgs(config.encoder, path, config.bitRate),
    ];

    _ffmpegProcess = await Process.start(_ffmpegExecutable, ffmpegArgs);
    // ffmpeg reports progress on stderr for as long as it encodes. Nobody
    // reads it, so once the pipe buffer is full ffmpeg blocks in write(),
    // stops reading stdin and the recording silently stops growing; stop()
    // then waits forever for the input pipe to drain.
    _drain(_ffmpegProcess!.stdout);
    _drain(_ffmpegProcess!.stderr);

    // Create a passthrough stream controller to intercept audio data
    _inputPcmController = StreamController<List<int>>();

    // Listen to raw PCM data from parecord:
    // 1. Calculate amplitude for VU meter
    // 2. Forward the unchanged PCM data to our stream controller
    parecordProc.stdout.listen((data) {
      final typed = data is Uint8List ? data : Uint8List.fromList(data);
      _amplitude.update(typed);

      if (_inputPcmController case final ctrl? when !ctrl.isClosed) {
        ctrl.add(typed);
      }
    }, onDone: () => _inputPcmController?.close());

    // Pipe the PCM data from our controller to ffmpeg for encoding
    // This uses pipe() for proper backpressure handling.
    // pipe() closes stdin itself when the stream ends.
    _ffmpegPipeDone = _inputPcmController!.stream.pipe(_ffmpegProcess!.stdin);
  }
}
