import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/codec_caps.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

void main() {
  test('supports the encoders ffmpeg is called with', () {
    expect(supportsEncoder(AudioEncoder.aacLc), isTrue);
    expect(supportsEncoder(AudioEncoder.flac), isTrue);
    expect(supportsEncoder(AudioEncoder.opus), isTrue);
    expect(supportsEncoder(AudioEncoder.wav), isTrue);
    expect(supportsEncoder(AudioEncoder.pcm16bits), isTrue);
  });

  test('rejects the others', () {
    expect(supportsEncoder(AudioEncoder.aacHe), isFalse);
    expect(supportsEncoder(AudioEncoder.amrNb), isFalse);
  });

  test('snaps opus to its nearest valid rate', () {
    expect(adjustSampleRate(AudioEncoder.opus, 44100), 48000);
    expect(adjustSampleRate(AudioEncoder.opus, 22050), 24000);
    expect(adjustSampleRate(AudioEncoder.opus, 48000), 48000);
  });

  test('leaves wav and flac rates alone', () {
    expect(adjustSampleRate(AudioEncoder.wav, 44100), 44100);
    expect(adjustSampleRate(AudioEncoder.flac, 37000), 37000);
  });

  test('returns the same config when nothing needs changing', () {
    const config = RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100);

    expect(identical(adjustConfig(config), config), isTrue);
  });

  test('clamps the channel count to stereo', () {
    const config = RecordConfig(encoder: AudioEncoder.wav, numChannels: 6);

    expect(adjustConfig(config).numChannels, 2);
  });

  test('adjusts the rate opus cannot use', () {
    const config = RecordConfig(encoder: AudioEncoder.opus, sampleRate: 44100);

    expect(adjustConfig(config).sampleRate, 48000);
  });
}
