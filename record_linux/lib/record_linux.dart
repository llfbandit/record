import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:record_platform_interface/record_platform_interface.dart';

const _parecordBin = 'parecord';
const _ffmpegBin = 'ffmpeg';

class RecordLinux extends RecordPlatform {
  static void registerWith() {
    RecordPlatform.instance = RecordLinux();
  }

  RecordState _state = RecordState.stop;
  String? _path;
  StreamController<RecordState>? _stateStreamCtrl;
  Process? _parecordProcess;
  Process? _ffmpegProcess;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) {
    _stateStreamCtrl?.close();
    return stop(recorderId);
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) {
    return Future.value(Amplitude(current: -160.0, max: -160.0));
  }

  @override
  Future<bool> hasPermission(String recorderId) {
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

    bool isParecordEncoder = _isParecordEncoder(config);

    final args = _getParecordArgs(
      config,
      path: path,
      canEncode: isParecordEncoder,
    );
    _parecordProcess = await Process.start(_parecordBin, args);

    // Only use ffmpeg when parecord can't encode.
    if (!isParecordEncoder) {
      _startFfmpeg(config, _parecordProcess!, path);
    }

    _path = path;
    _updateState(RecordState.record);
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    await stop(recorderId);

    final args = _getParecordArgs(config);
    _parecordProcess = await Process.start(_parecordBin, args);

    _updateState(RecordState.record);

    return _parecordProcess!.stdout.map((list) {
      return (list is Uint8List) ? list : Uint8List.fromList(list);
    });
  }

  @override
  Future<String?> stop(String recorderId) async {
    final path = _path;

    _parecordProcess?.kill();
    _parecordProcess = null;
    _ffmpegProcess = null;
    _path = null;

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
    _stateStreamCtrl ??= StreamController();
    return _stateStreamCtrl!.stream;
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

  bool _isParecordEncoder(RecordConfig config) {
    bool parecordCanEncode = switch (config.encoder) {
      AudioEncoder.flac || AudioEncoder.wav || AudioEncoder.pcm16bits => true,
      _ => false
    };
    return parecordCanEncode;
  }

  List<String> _getParecordArgs(
    RecordConfig config, {
    String? path,
    bool canEncode = false,
  }) {
    final numChannels = _getNumChannels(config);

    final args = [
      '--raw',
      '--format=s16le',
      '--rate=${config.sampleRate}',
      '--channels=$numChannels',
      '--latency-msec=100',
      if (config.device != null) '--device=${config.device!.id}',
      if (config.autoGain) '--property=auto_gain_control=1',
      if (config.echoCancel) '--property=echo_cancellation=1',
      if (config.noiseSuppress) '--property=noise_suppression=1',
      if (canEncode) ...[
        '--file-format=${config.encoder.name}',
        if (path case final path?) path,
      ],
    ];

    return args;
  }

  int _getNumChannels(RecordConfig config) {
    return config.numChannels.clamp(1, 2);
  }

  Future<void> _startFfmpeg(
    RecordConfig config,
    Process parecordProc,
    String path,
  ) async {
    /// Constructs the arguments for the FFmpeg command.
    ///
    /// The arguments include:
    /// - `-f`: Specifies the format of the input data. In this case, 's16le' which stands for signed 16-bit little-endian.
    /// - `-ar`: Sets the audio sampling rate. The value is obtained from `config.sampleRate`.
    /// - `-ac`: Sets the number of audio channels. The value is provided by `numChannels`.
    /// - `-i`: Specifies the input file. Here, '-' indicates that the input is from standard input (stdin) from the parecord Process.
    /// - `_getFfmpegEncoderSettings`: A function that returns additional encoder settings based on the provided encoder type, output path, and bit rate.
    final ffmpegArgs = [
      '-f',
      's16le',
      '-ar',
      config.sampleRate.toString(),
      '-ac',
      '${_getNumChannels(config)}',
      '-i',
      '-',
      ..._getFfmpegEncoderSettings(config.encoder, path, config.bitRate)
    ];

    _ffmpegProcess = await Process.start(_ffmpegBin, ffmpegArgs);
    parecordProc.stdout.pipe(_ffmpegProcess!.stdin);
  }

  List<String> _getFfmpegEncoderSettings(
      AudioEncoder encoder, String path, int bitRate) {
    switch (encoder) {
      case AudioEncoder.aacLc:
        return ['-c:a', 'aac', '-b:a', '${bitRate / 1000}k', path];
      // case AudioEncoder.wav:
      //   return ['-c:a', 'pcm_s16le', path];
      case AudioEncoder.flac:
        return ['-c:a', 'flac', path];
      case AudioEncoder.opus:
        return ['-c:a', 'libopus', '-b:a', '${bitRate / 1000}k', path];
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
    final process = await Process.start('pactl', arguments);

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

    for (final line in output) {
      if (line.startsWith('Source #')) {
        if (currentDeviceId != null && currentDeviceName != null) {
          if (!currentDeviceName.startsWith('Monitor of')) {
            devices.add(
                InputDevice(id: currentDeviceId, label: currentDeviceName));
          }
        }
      } else if (line.trim().startsWith('node.name')) {
        currentDeviceId = line.split('=')[1].trim();
      } else if (line.trim().startsWith('Name:')) {
        currentDeviceName = line.split(':')[1].trim();
      } else if (line.trim().startsWith('Description:')) {
        currentDeviceName = line.split(':')[1].trim();
      }
    }

    if (currentDeviceId != null && currentDeviceName != null) {
      if (!currentDeviceName.startsWith('Monitor of')) {
        devices.add(InputDevice(id: currentDeviceId, label: currentDeviceName));
      }
    }

    return devices;
  }

  void _updateState(RecordState state) {
    if (_state == state) return;

    _state = state;

    if (_stateStreamCtrl?.hasListener ?? false) {
      _stateStreamCtrl?.add(state);
    }
  }
}
