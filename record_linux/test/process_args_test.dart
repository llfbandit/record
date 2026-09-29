import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/process_args.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

void main() {
  test('always captures raw s16le', () {
    final args = parecordArgs(const RecordConfig(sampleRate: 16000));

    expect(args, containsAll(['--raw', '--format=s16le', '--rate=16000']));
  });

  test('passes the device id through', () {
    final args = parecordArgs(
      const RecordConfig(
        device: InputDevice(id: 'alsa_input.usb-Blue-00', label: 'Blue'),
      ),
    );

    expect(args, contains('--device=alsa_input.usb-Blue-00'));
  });

  test('leaves out the audio processing flags by default', () {
    final args = parecordArgs(const RecordConfig());

    expect(args.where((a) => a.startsWith('--property=')), isEmpty);
  });

  test('ffmpeg captures raw s16le from ALSA on stdout', () {
    final args = ffmpegAlsaCaptureArgs(
      const RecordConfig(sampleRate: 16000, numChannels: 1),
      defaultDevice: 'default',
    );

    // The parecord path produces the same raw stream, so everything
    // downstream (amplitude, the encoder) is untouched by the backend.
    expect(args, containsAllInOrder(['-f', 'alsa', '-i', 'default']));
    expect(args, containsAllInOrder(['-ar', '16000']));
    expect(args, containsAllInOrder(['-ac', '1']));
    expect(args, containsAllInOrder(['-f', 's16le', '-']));
    // Capture is driven by the plugin; ffmpeg must not read the host stdin.
    expect(args, contains('-nostdin'));
  });

  test('ffmpeg records the selected ALSA device', () {
    final args = ffmpegAlsaCaptureArgs(
      const RecordConfig(
        device: InputDevice(id: 'hw:1,0', label: 'Blue'),
      ),
      defaultDevice: 'default',
    );

    expect(args, containsAllInOrder(['-i', 'hw:1,0']));
    expect(args, isNot(contains('default')));
  });

  test('adds a file format only when parecord encodes', () {
    final args = parecordArgs(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: '/tmp/out.wav',
      canEncode: true,
    );

    expect(args, containsAll(['--file-format=wav', '/tmp/out.wav']));
  });

  test('sends the bit rate to ffmpeg in kbit', () {
    final args = ffmpegEncoderArgs(AudioEncoder.aacLc, '/tmp/a.m4a', 128000);

    expect(args, ['-c:a', 'aac', '-b:a', '128k', '/tmp/a.m4a']);
  });

  test('copies pcm instead of re-encoding it', () {
    final args = ffmpegEncoderArgs(
      AudioEncoder.pcm16bits,
      '/tmp/a.pcm',
      128000,
    );

    expect(args, ['-c:a', 'copy', '-f', 's16le', '/tmp/a.pcm']);
  });

  test('returns nothing for an unsupported encoder', () {
    expect(ffmpegEncoderArgs(AudioEncoder.amrNb, '/tmp/a', 128000), isEmpty);
  });
}
