import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:record_platform_interface/record_platform_interface.dart';

const _arecordBin = 'arecord';
const _ffmpegBin = 'ffmpeg';

class RecordLinux extends RecordPlatform {
  static void registerWith() {
    RecordPlatform.instance = RecordLinux();
  }

  RecordState _state = RecordState.stop;
  String? _path;
  StreamController<RecordState>? _stateStreamCtrl;
  Process? _arecordProcess;

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
      _arecordProcess?.kill(ProcessSignal.sigstop);
      _updateState(RecordState.pause);
    }
  }

  @override
  Future<void> resume(String recorderId) async {
    if (_state == RecordState.pause) {
      _arecordProcess?.kill(ProcessSignal.sigcont);
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

    final args = [
      '-f',
      'cd',
      '-r',
      config.sampleRate.toString(),
      '-c',
      numChannels,
      '-t',
      'raw',
      '-'
    ];

    _arecordProcess = await Process.start(_arecordBin, args);

    final ffmpegArgs = [
      '-f',
      's16le',
      '-ar',
      config.sampleRate.toString(),
      '-ac',
      numChannels,
      '-i',
      '-',
      ..._getEncoderSettings(config.encoder, path)
    ];

    final ffmpegProcess = await Process.start(_ffmpegBin, ffmpegArgs);
    _arecordProcess!.stdout.pipe(ffmpegProcess.stdin);

    _arecordProcess!.stderr.listen((event) {});
    ffmpegProcess.stderr.listen((event) {});

    _path = path;
    _updateState(RecordState.record);
  }

  @override
  Future<String?> stop(String recorderId) async {
    final path = _path;

    _arecordProcess?.kill();
    _arecordProcess = null;

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

  Future<void> _callArecord(
    List<String> arguments, {
    required String recorderId,
    StreamController<List<int>>? outStreamCtrl,
    VoidCallback? onStarted,
    bool consumeOutput = true,
  }) async {
    final process = await Process.start('arecord', arguments);

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

    for (final line in output) {
      if (line.startsWith('card')) {
        final parts = line.split(':');
        final cardInfo = parts[0].split(' ');
        final cardId = cardInfo[1];
        final cardName = parts[1].trim();
        devices.add(InputDevice(id: cardId, label: cardName));
      } else if (line.startsWith('    Subdevice')) {
        final subdeviceInfo = line.split(':');
        final subdeviceName = subdeviceInfo[1].trim();
        final lastDevice = devices.last;
        devices.add(InputDevice(id: lastDevice.id, label: '${lastDevice.label} - $subdeviceName'));
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
      await _callArecord(['-l'], recorderId: recorderId, outStreamCtrl: outStreamCtrl);

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

  List<String> _getEncoderSettings(AudioEncoder encoder, String path) {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacHe:
        return ['-c:a', 'aac', '-b:a', '128k', path];
      case AudioEncoder.wav:
        return ['-c:a', 'pcm_s16le', path];
      case AudioEncoder.flac:
        return ['-c:a', 'flac', path];
      case AudioEncoder.opus:
        return ['-c:a', 'libopus', '-b:a', '128k', path];
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
