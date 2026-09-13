import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:record_platform_interface/record_platform_interface.dart';

const _parecordBin = 'parecord';
const _ffmpegBin = 'ffmpeg';

class RecordLinux extends RecordPlatform {
  RecordLinux({
    @visibleForTesting String parecordBin = _parecordBin,
    @visibleForTesting String ffmpegBin = _ffmpegBin,
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
  double _currentAmplitude = -160.0;
  double _maxAmplitude = -160.0;
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
    return Future.value(
      Amplitude(current: _currentAmplitude, max: _maxAmplitude),
    );
  }

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) {
    return Future.value(true);
  }

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.flac:
      case AudioEncoder.opus:
      case AudioEncoder.wav:
      case AudioEncoder.pcm16bits:
        return true;
      default:
        return false;
    }
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

    await _supportedOrThrow(recorderId, config);

    _deleteFile(path);

    final adjustedConfig = _adjustConfig(config);

    // Step 1: Use parecord to capture raw PCM audio from the microphone
    // We always capture raw PCM (not encoded) so we can calculate amplitude
    final args = _getParecordArgs(adjustedConfig, path: null, canEncode: false);
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

    final args = _getParecordArgs(adjustedConfig);
    _parecordProcess = await Process.start(_parecordExecutable, args);
    _drain(_parecordProcess!.stderr);

    _updateState(RecordState.record);

    return _parecordProcess!.stdout.map((list) {
      final data = (list is Uint8List) ? list : Uint8List.fromList(list);
      // Calculate amplitude from PCM data
      _calculateAmplitude(data);
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

    // Reset amplitude values
    _currentAmplitude = -160.0;
    _maxAmplitude = -160.0;

    _updateState(RecordState.stop);

    return path;
  }

  @override
  Future<void> cancel(String recorderId) async {
    final path = await stop(recorderId);

    _deleteFile(path);
  }

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async {
    final outStreamCtrl = StreamController<List<int>>();

    final out = <String>[];
    outStreamCtrl.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((chunk) {
          out.add(chunk);
        });

    try {
      await _callPactl(
        ['list', 'sources'],
        recorderId: recorderId,
        outStreamCtrl: outStreamCtrl,
      );

      return _parseInputDevices(out);
    } finally {
      outStreamCtrl.close();
    }
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

  Future<void> _supportedOrThrow(String recorderId, RecordConfig config) async {
    final supported = await isEncoderSupported(recorderId, config.encoder);
    if (!supported) {
      throw Exception('${config.encoder} is not supported.');
    }
  }

  List<String> _getParecordArgs(
    RecordConfig config, {
    String? path,
    bool canEncode = false,
  }) {
    final args = [
      '--raw',
      '--format=s16le',
      '--rate=${config.sampleRate}',
      '--channels=${config.numChannels}',
      '--latency-msec=100',
      if (config.device != null) '--device=${config.device!.id}',
      if (config.autoGain) '--property=auto_gain_control=1',
      if (config.echoCancel) '--property=echo_cancellation=1',
      if (config.noiseSuppress) '--property=noise_suppression=1',
      if (canEncode) ...['--file-format=${config.encoder.name}', ?path],
    ];

    return args;
  }

  List<String> _getFfmpegEncoderSettings(
    AudioEncoder encoder,
    String path,
    int bitRate,
  ) {
    switch (encoder) {
      case AudioEncoder.aacLc:
        return ['-c:a', 'aac', '-b:a', '${bitRate ~/ 1000}k', path];
      case AudioEncoder.wav:
        return ['-c:a', 'pcm_s16le', '-f', 'wav', path];
      case AudioEncoder.flac:
        return ['-c:a', 'flac', path];
      case AudioEncoder.opus:
        return ['-c:a', 'libopus', '-b:a', '${bitRate ~/ 1000}k', path];
      case AudioEncoder.pcm16bits:
        return ['-c:a', 'copy', '-f', 's16le', path];
      default:
        return [];
    }
  }

  Future<void> _callPactl(
    List<String> arguments, {
    required String recorderId,
    StreamController<List<int>>? outStreamCtrl,
    VoidCallback? onStarted,
    bool consumeOutput = true,
  }) async {
    // Force LC_ALL=C for pactl output to ensure consistent parsing
    final process = await Process.start(
      'pactl',
      arguments,
      environment: {"LC_ALL": "C"},
    );

    if (onStarted != null) {
      onStarted();
    }

    // Listen to both stdout & stderr to not leak system resources.
    if (consumeOutput) {
      final out = outStreamCtrl ?? StreamController<List<int>>();
      if (outStreamCtrl == null) out.stream.listen((event) {});
      final err = StreamController<List<int>>();
      err.stream.listen((event) {});

      await Future.wait([
        out.addStream(process.stdout),
        err.addStream(process.stderr),
      ]);

      if (outStreamCtrl == null) out.close();
      err.close();
    }
  }

  // Output can be retrieved with `pactl list sources`
  // --- Example ---
  // Source #2325
  // State: SUSPENDED
  // Name: alsa_output.usb-Generic_Blue_Microphones_LT_2201070607069D01069D_111000-00.analog-stereo.monitor
  // Description: Monitor of Blue Microphones Analog Stereo
  // Driver: PipeWire
  // Sample Specification: s16le 2ch 48000Hz
  // Channel Map: front-left,front-right
  // Owner Module: 4294967295
  // Mute: no
  // Volume: front-left: 65536 / 100% / 0.00 dB,   front-right: 65536 / 100% / 0.00 dB
  //         balance 0.00
  // Base Volume: 65536 / 100% / 0.00 dB
  // Monitor of Sink: alsa_output.usb-Generic_Blue_Microphones_LT_2201070607069D01069D_111000-00.analog-stereo
  // Latency: 0 usec, configured 0 usec
  // Flags: HARDWARE DECIBEL_VOLUME LATENCY
  // Properties:
  // 	alsa.card = "2"
  // 	alsa.card_name = "Blue Microphones"
  // 	alsa.class = "generic"
  // 	alsa.components = "USB046d:0ab7"
  //  node.name = "alsa_input.usb-Generic_Blue_Microphones_LT_2201070607069D01069D_111000-00.analog-stereo"
  List<InputDevice> _parseInputDevices(List<String> output) {
    final devices = <InputDevice>[];
    String? currentDeviceId;
    String? currentDeviceName;
    List<int> currentSampleRates = [];

    void commitDevice() {
      if (currentDeviceId != null &&
          currentDeviceName != null &&
          !currentDeviceId.endsWith('.monitor') &&
          !currentDeviceName.startsWith('Monitor of')) {
        devices.add(
          InputDevice(
            id: currentDeviceId,
            label: currentDeviceName,
            sampleRates: currentSampleRates,
          ),
        );
      }
    }

    for (final line in output) {
      if (line.startsWith('Source #')) {
        commitDevice();
        currentDeviceId = null;
        currentDeviceName = null;
        currentSampleRates = [];
      } else if (line.trim().startsWith('node.name')) {
        currentDeviceId = line.split('=')[1].trim();
      } else if (line.trim().startsWith('Name:')) {
        currentDeviceName = line.substring(line.indexOf(':') + 1).trim();
      } else if (line.trim().startsWith('Description:')) {
        currentDeviceName = line.substring(line.indexOf(':') + 1).trim();
      } else if (line.trim().startsWith('Sample Specification:')) {
        final match = RegExp(r'(\d+)Hz').firstMatch(line);
        if (match != null) {
          currentSampleRates = [int.parse(match.group(1)!)];
        }
      }
    }

    commitDevice();

    return devices;
  }

  RecordConfig _adjustConfig(RecordConfig config) {
    final sampleRate = _adjustSampleRate(config.encoder, config.sampleRate);
    final numChannels = config.numChannels.clamp(1, 2);

    if (sampleRate == config.sampleRate && numChannels == config.numChannels) {
      return config;
    }

    config = config.copyWith(sampleRate: sampleRate, numChannels: numChannels);

    _configChangedHandler?.call(config);

    return config;
  }

  int _adjustSampleRate(AudioEncoder encoder, int sampleRate) {
    final List<int> validRates;
    switch (encoder) {
      case AudioEncoder.opus:
        validRates = const [8000, 12000, 16000, 24000, 48000];
      case AudioEncoder.aacLc:
        validRates = const [
          8000,
          11025,
          12000,
          16000,
          22050,
          24000,
          32000,
          44100,
          48000,
          64000,
          88200,
          96000,
        ];
      default:
        return sampleRate;
    }
    return validRates.reduce(
      (a, b) => (a - sampleRate).abs() <= (b - sampleRate).abs() ? a : b,
    );
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

  void _calculateAmplitude(Uint8List data) {
    if (data.isEmpty) return;

    // Convert bytes to 16-bit signed integers (little-endian)
    double maxSample = 0;
    for (int i = 0; i < data.length - 1; i += 2) {
      // Combine two bytes into a 16-bit signed integer (little-endian)
      int sample = data[i] | (data[i + 1] << 8);
      // Convert unsigned to signed
      if (sample > 32767) sample -= 65536;

      double absSample = sample.abs().toDouble();
      if (absSample > maxSample) {
        maxSample = absSample;
      }
    }

    // Calculate dBFS
    if (maxSample > 0) {
      _currentAmplitude = 20 * (log(maxSample / 32767.0) / ln10);
    } else {
      _currentAmplitude = -160.0;
    }

    // Update max amplitude
    if (_currentAmplitude > _maxAmplitude) {
      _maxAmplitude = _currentAmplitude;
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
      ..._getFfmpegEncoderSettings(config.encoder, path, config.bitRate),
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
      _calculateAmplitude(typed);

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
