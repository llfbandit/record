import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:record_platform_interface/record_platform_interface.dart';

///relative path to
const _assetsDir =
    'data\\flutter_assets\\packages\\record_windows\\assets\\fmedia';

const _pipeProcName = 'record_windows';

class RecordWindows extends RecordPlatform {
  static void registerWith() {
    RecordPlatform.instance = RecordWindows();
  }

  // fmedia pID
  int? _pid;
  bool _isRecording = false;
  bool _isPaused = false;
  String? _path;

  @override
  Future<void> dispose() {
    if (_pid != null) {
      Process.killPid(_pid!, ProcessSignal.sigterm);
      _pid = null;
    }

    _isRecording = false;
    _isPaused = false;

    return Future.value();
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
        return true;
      case AudioEncoder.flac:
        return true;
      case AudioEncoder.opus:
        return true;
      case AudioEncoder.wav:
        return true;
      case AudioEncoder.vorbisOgg:
        return true;
      default:
        return false;
    }
  }

  @override
  Future<bool> isPaused() {
    return Future.value(_isPaused);
  }

  @override
  Future<bool> isRecording() {
    return Future.value(_isRecording);
  }

  @override
  Future<void> pause() async {
    await _callFMedia(['--globcmd=pause']);

    _isPaused = true;
  }

  @override
  Future<void> resume() async {
    await _callFMedia(['--globcmd=unpause']);

    _isRecording = true;
  }

  @override
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
  }) async {
    path ??= p.join(
      Directory.systemTemp.path,
      Random.secure().nextInt(1000000000).toRadixString(16),
    );

    path = p.withoutExtension(p.normalize(path));
    path += _getFileNameSuffix(encoder);

    final file = File(path);
    if (file.existsSync()) await file.delete();

    _path = path;

    _pid = await _callFMedia([
      '--record',
      '--out=$path',
      '--rate=$samplingRate',
      '--channels=2',
      '--globcmd=listen',
      '--gain=6.0',
      ..._getEncoderSettings(encoder, bitRate),
    ]);

    _isRecording = true;
  }

  @override
  Future<String?> stop() async {
    await _callFMedia(['--globcmd=stop']);

    _isRecording = false;
    _isPaused = false;

    return _path;
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
        return ['--flac-compression=6'];
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
    if (rate <= 320) {
      final quality = (rate / 64).ceil().clamp(1, 5).toInt();
      return ['--aac-quality=$quality'];
    }

    final quality = rate.clamp(8, 800).toInt();
    return ['--aac-quality=$quality'];
  }

  Future<int> _callFMedia(List<String> arguments) async {
    final result = await Process.run('$_assetsDir\\fmedia.exe', [
      '--globcmd.pipe-name=$_pipeProcName',
      ...arguments,
    ]);

    return result.pid;
  }
}
