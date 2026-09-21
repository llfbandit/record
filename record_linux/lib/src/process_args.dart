import 'package:record_platform_interface/record_platform_interface.dart';

List<String> parecordArgs(
  RecordConfig config, {
  String? path,
  bool canEncode = false,
}) {
  return [
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
}

/// Returns the ffmpeg output arguments for [encoder].
List<String> ffmpegEncoderArgs(AudioEncoder encoder, String path, int bitRate) {
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
