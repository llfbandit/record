import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:record_platform_interface/record_platform_interface.dart';

const _fmediaPath = 'fmedia';
const _fmediaBin = 'fmedia.exe';

const _pipeProcName = 'record_windows';

class RecordWindows extends RecordPlatform {
  static void registerWith() {
    RecordPlatform.instance = RecordWindows();
  }

  // fmedia pID
  int? _pid;
  RecordState _state = RecordState.stop;
  String? _path;
  StreamSubscription<String>? _fmediaSub;
  StreamController<RecordState>? _stateStreamCtrl;

  @override
  Future<void> dispose() {
    _fmediaSub?.cancel();
    _stateStreamCtrl?.close();

    return stop().then((value) {
      if (_pid != null) {
        Process.killPid(_pid!, ProcessSignal.sigterm);
        _pid = null;
      }

      return Future.value();
    });
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
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
    int numChannels = 2,
    InputDevice? device,
  }) async {
    await stop();

    path ??= p.join(
      Directory.systemTemp.path,
      Random.secure().nextInt(1000000000).toRadixString(16),
    );

    path = p.withoutExtension(p.normalize(path));
    path += _getFileNameSuffix(encoder);

    final file = File(path);
    if (file.existsSync()) await file.delete();

    final process = await _callFMedia([
      '--notui',
      '--background',
      '--record',
      '--out=$path',
      '--rate=$samplingRate',
      '--channels=$numChannels',
      '--globcmd=listen',
      '--gain=6.0',
      if (device != null) '--dev-capture=${device.id}',
      ..._getEncoderSettings(encoder, bitRate),
    ]);
    _pid = process.pid;
    _path = path;

    _updateState(RecordState.record);

    // Print the fmedia output to allow diagnostics.
    _fmediaSub?.cancel();
    _fmediaSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((chunk) {
      if (kDebugMode) print(chunk);
    });
    _fmediaSub!.onDone(() {
      _fmediaSub?.cancel();
      _path = null;
      stop();
    });
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
    final process = await _callFMedia(['--list-dev']);

    final completer = Completer<List<InputDevice>>();

    final out = <String>[];
    StreamSubscription<String>? sub;
    sub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((chunk) {
      out.add(chunk);
    })
      ..onDone(() {
        sub?.cancel();
        completer.complete(_listInputDevices(out));
      });

    return completer.future;
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

  String _getFileNameSuffix(AudioEncoder encoder) {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacHe:
        return '.m4a';
      case AudioEncoder.flac:
        return '.flac';
      case AudioEncoder.opus:
        return '.opus';
      case AudioEncoder.wav:
        return '.wav';
      case AudioEncoder.vorbisOgg:
        return '.ogg';
      default:
        return '.m4a';
    }
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

  Future<Process> _callFMedia(List<String> arguments) {
    final path = File(Platform.resolvedExecutable).parent.path;

    return Process.start(p.join(path, _fmediaPath, _fmediaBin), [
      '--globcmd.pipe-name=$_pipeProcName',
      ...arguments,
    ]);
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

    void _extract({String? secondLine}) {
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
        _extract();
        deviceLine = line;
      } else if (line.startsWith(RegExp(r'^\s*Default Format: '))) {
        _extract(secondLine: line);
      }
    }

    // Extract previous device if second line was missing
    _extract();

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
