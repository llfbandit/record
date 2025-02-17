import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

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
      String recorderId, AudioEncoder encoder) async {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacHe:
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

  final file = File(path);
  if (file.existsSync()) await file.delete();

  final supported = await isEncoderSupported(recorderId, config.encoder);
  if (!supported) {
    throw Exception('${config.encoder} is not supported.');
  }

  String numChannels;
  if (config.numChannels == 1 || config.numChannels == 2) {
    numChannels = config.numChannels.toString();
  } else {
    throw Exception('${config.numChannels} config is not supported.');
  }

  bool parecordCanEncode = config.encoder == AudioEncoder.flac || config.encoder == AudioEncoder.wav;

  final args = [
    '--raw',
    '--format=s16le',
    '--rate=${config.sampleRate}',
    '--channels=$numChannels',
    '--latency-msec=100',
    if (parecordCanEncode) '--file-format=${config.encoder.name}',
    if (config.device != null) '--device=${config.device!.id}',
    if (config.autoGain) '--property=auto_gain_control=1',
    if (config.echoCancel) '--property=echo_cancellation=1',
    if (config.noiseSuppress) '--property=noise_suppression=1',
    if (parecordCanEncode) path,
  ];

  _parecordProcess = await Process.start(_parecordBin, args);

  // parecord can output flac and wav directly, only use ffmpeg for other encoders
  if (!parecordCanEncode) {
    
    final ffmpegArgs = [
      '-f',
      's16le',
      '-ar',
      config.sampleRate.toString(),
      '-ac',
      numChannels,
      '-i',
      '-',
      ..._getEncoderSettings(config.encoder, path, config.bitRate)
    ];

    _ffmpegProcess = await Process.start(_ffmpegBin, ffmpegArgs);
    _parecordProcess!.stdout.pipe(_ffmpegProcess!.stdin);
  }

  _path = path;
  _updateState(RecordState.record);
}

  @override
  Future<String?> stop(String recorderId) async {
    final path = _path;

    _parecordProcess?.kill();
    _parecordProcess = null;
    _ffmpegProcess = null;

    _updateState(RecordState.stop);

    return path;
  }

  @override
  Future<void> cancel(String recorderId) async {
    final path = await stop(recorderId);

    if (path != null) {
      final file = File(path);

      if (file.existsSync()) {
        file.deleteSync();
      }
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

  List<InputDevice> _parseInputDevices(List<String> output) {
    final devices = <InputDevice>[];
    String? currentDeviceId;
    String? currentDeviceName;

    for (final line in output) {
      if (line.startsWith('Source #')) {
        if (currentDeviceId != null && currentDeviceName != null) {
          if (!currentDeviceName.startsWith('Monitor of')) {
            devices.add(InputDevice(id: currentDeviceId, label: currentDeviceName));
          }
        }
        currentDeviceId = line.split('#')[1].trim();
        currentDeviceName = null;
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
      await _callPactl(['list', 'sources'], recorderId: recorderId, outStreamCtrl: outStreamCtrl);

      return _parseInputDevices(out);
    } finally {
      outStreamCtrl.close();
    }
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) {
    _stateStreamCtrl ??= StreamController(
      onCancel: () {
        _stateStreamCtrl?.close();
        _stateStreamCtrl = null;
      },
    );

    return _stateStreamCtrl!.stream;
  }

  List<String> _getEncoderSettings(AudioEncoder encoder, String path, int bitRate) {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacHe:
        return ['-c:a', 'aac', '-b:a', '${bitRate/1000}k', path];
      case AudioEncoder.wav:
        return ['-c:a', 'pcm_s16le', path];
      case AudioEncoder.flac:
        return ['-c:a', 'flac', path];
      case AudioEncoder.opus:
        return ['-c:a', 'libopus', '-b:a', '${bitRate/1000}k', path];
      default:
        return [];
    }
  }

  void _updateState(RecordState state) {
    if (_state == state) return;

    _state = state;

    if (_stateStreamCtrl?.hasListener ?? false) {
      _stateStreamCtrl?.add(state);
    }
  }
}
