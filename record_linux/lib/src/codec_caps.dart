import 'package:record_platform_interface/record_platform_interface.dart';

bool supportsEncoder(AudioEncoder encoder) {
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

/// Returns [config] with a sample rate and channel count the encoder accepts.
RecordConfig adjustConfig(RecordConfig config) {
  final sampleRate = adjustSampleRate(config.encoder, config.sampleRate);
  final numChannels = config.numChannels.clamp(1, 2);

  if (sampleRate == config.sampleRate && numChannels == config.numChannels) {
    return config;
  }

  return config.copyWith(sampleRate: sampleRate, numChannels: numChannels);
}

/// Returns the rate [encoder] accepts that is closest to [sampleRate].
int adjustSampleRate(AudioEncoder encoder, int sampleRate) {
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
