import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

const _fmediaBin = 'fmedia';

const _pipeProcName = 'record_linux';

class RecordLinux extends RecordPlatform {
  static void registerWith() {
    RecordPlatform.instance = RecordLinux();
  }

  RecordState _state = RecordState.stop;
  String? _path;
  StreamController<RecordState>? _stateStreamCtrl;

  @override
  Future<void> dispose() {
    _stateStreamCtrl?.close();
    return stop();
  }

  @override
  Future<Amplitude> getAmplitude() {
    return Future.value(Amplitude(current: -160.0, max: -160.0));
  }

  @override
  Future<bool> hasPermission() {
    return Future.value(true);
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacHe:
      case AudioEncoder.flac:
      case AudioEncoder.opus:
      case AudioEncoder.wav:
      case AudioEncoder.vorbisOgg:
        return true;
      default:
        return false;
    }
  }

  @override
  Future<bool> isPaused() {
    return Future.value(_state == RecordState.pause);
  }

  @override
  Future<bool> isRecording() {
    return Future.value(_state == RecordState.record);
  }

  @override
  Future<void> pause() async {
    if (_state == RecordState.record) {
      await _callFMedia(['--globcmd=pause']);

      _updateState(RecordState.pause);
    }
  }

  @override
  Future<void> resume() async {
    if (_state == RecordState.pause) {
      await _callFMedia(['--globcmd=unpause']);

      _updateState(RecordState.record);
    }
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    await stop();

    final file = File(path);
    if (file.existsSync()) await file.delete();

    await _callFMedia(
      [
        '--notui',
        '--background',
        '--record',
        '--out=$path',
        '--rate=${config.samplingRate}',
        '--channels=${config.numChannels}',
        '--globcmd=listen',
        '--gain=6.0',
        if (config.device != null) '--dev-capture=${config.device!.id}',
        ..._getEncoderSettings(config.encoder, config.bitRate),
      ],
      onStarted: () {
        _path = path;
        _updateState(RecordState.record);
      },
      consumeOutput: false,
    );
  }

  @override
  Future<String?> stop() async {
    final path = _path;

    await _callFMedia(['--globcmd=stop']);
    await _callFMedia(['--globcmd=quit']);

    _updateState(RecordState.stop);

    return path;
  }

  @override
  Future<List<InputDevice>> listInputDevices() async {
    final outStreamCtrl = StreamController<List<int>>();

    final out = <String>[];
    outStreamCtrl.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((chunk) {
      out.add(chunk);
    });

    try {
      await _callFMedia(['--list-dev'], outStreamCtrl: outStreamCtrl);

      return _listInputDevices(out);
    } finally {
      outStreamCtrl.close();
    }
  }

  @override
  Stream<RecordState> onStateChanged() {
    _stateStreamCtrl ??= StreamController(
      onCancel: () {
        _stateStreamCtrl?.close();
        _stateStreamCtrl = null;
      },
    );

    return _stateStreamCtrl!.stream;
  }

  List<String> _getEncoderSettings(AudioEncoder encoder, int bitRate) {
    switch (encoder) {
      case AudioEncoder.aacLc:
        return ['--aac-profile=LC', ..._getAacQuality(bitRate)];
      case AudioEncoder.aacHe:
        return ['--aac-profile=HEv2', ..._getAacQuality(bitRate)];
      case AudioEncoder.flac:
        return ['--flac-compression=6', '--format=int16'];
      case AudioEncoder.opus:
        final rate = (bitRate ~/ 1000).clamp(6, 510);
        return ['--opus.bitrate=$rate'];
      case AudioEncoder.wav:
        return [];
      case AudioEncoder.vorbisOgg:
        return ['--vorbis.quality=6.0'];
      default:
        return [];
    }
  }

  List<String> _getAacQuality(int bitRate) {
    final rate = bitRate ~/ 1000;
    // Prefer VBR
    // if (rate <= 320) {
    //   final quality = (rate / 64).ceil().clamp(1, 5).toInt();
    //   return ['--aac-quality=$quality'];
    // }

    final quality = rate.clamp(8, 800).toInt();
    return ['--aac-quality=$quality'];
  }

  Future<void> _callFMedia(
    List<String> arguments, {
    StreamController<List<int>>? outStreamCtrl,
    VoidCallback? onStarted,
    bool consumeOutput = true,
  }) async {
    final process = await Process.start(_fmediaBin, [
      '--globcmd.pipe-name=$_pipeProcName',
      ...arguments,
    ]);

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

  // Playback/Loopback:
  // device #1: FOO (High Definition Audio) - Default
  // Default Format: 2 channel, 48000 Hz
  // Capture:
  // device #1: Microphone (High Definition Audio Device) - Default
  // Default Format: 2 channel, 44100 Hz
  Future<List<InputDevice>> _listInputDevices(List<String> out) async {
    final devices = <InputDevice>[];
    var deviceLine = '';

    void extract({String? secondLine}) {
      if (deviceLine.isNotEmpty) {
        final device = _extractDevice(deviceLine, secondLine: secondLine);
        if (device != null) devices.add(device);
        deviceLine = '';
      }
    }

    var hasCaptureDevices = false;
    for (var line in out) {
      // Forwards to capture devices
      if (!hasCaptureDevices) {
        hasCaptureDevices = (line == 'Capture:');
        continue;
      }

      if (line.startsWith(RegExp(r'^device #'))) {
        // Extract previous device if second line was missing
        extract();
        deviceLine = line;
      } else if (line.startsWith(RegExp(r'^\s*Default Format:'))) {
        extract(secondLine: line);
      }
    }

    // Extract previous device if second line was missing
    extract();

    return devices;
  }

  InputDevice? _extractDevice(String firstLine, {String? secondLine}) {
    final match = RegExp(r'(?:.*device #)(\d+): (\w.+)').firstMatch(firstLine);
    if (match == null || match.groupCount != 2) return null;

    // ID
    final id = match.group(1);
    if (id == null) return null;

    // Label
    var label = match.group(2)!;
    // Remove default from label
    final index = label.indexOf(' - Default');
    if (index != -1) {
      label = label.substring(0, index);
    }

    int? channels;
    int? samplingRate;
    if (secondLine != null) {
      final match = RegExp(
        r'(?:.*Default Format: )(\d+) channel, (\d+) Hz',
      ).firstMatch(secondLine);

      if (match != null && match.groupCount == 2) {
        // Number of channels
        final channelsStr = match.group(1);
        channels = channelsStr != null ? int.tryParse(channelsStr) : null;

        // Sampling rate
        final samplingStr = match.group(2);
        samplingRate = samplingStr != null ? int.tryParse(samplingStr) : null;
      }
    }

    return InputDevice(
      id: id,
      label: label,
      channels: channels,
      samplingRate: samplingRate,
    );
  }

  void _updateState(RecordState state) {
    if (_state == state) return;

    _state = state;

    if (_stateStreamCtrl?.hasListener ?? false) {
      _stateStreamCtrl?.add(state);
    }
  }
}
