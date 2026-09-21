import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/pactl_devices.dart';

/// Parsing only, so this runs on any host without pactl.
void main() {
  const sources = [
    'Source #0',
    '\tState: SUSPENDED',
    '\tName: alsa_output.pci-0000_00_1f.3.analog-stereo.monitor',
    '\tDescription: Monitor of Built-in Audio Analog Stereo',
    '\tSample Specification: s16le 2ch 48000Hz',
    '\tProperties:',
    '\t\tnode.name = "alsa_output.pci-0000_00_1f.3.analog-stereo.monitor"',
    'Source #1',
    '\tState: RUNNING',
    '\tName: alsa_input.usb-Blue_Microphones-00.analog-stereo',
    '\tDescription: Blue Microphones: Analog Stereo',
    '\tSample Specification: s16le 2ch 44100Hz',
    '\tProperties:',
    '\t\tnode.name = "alsa_input.usb-Blue_Microphones-00.analog-stereo"',
  ];

  test('skips monitor sources', () {
    final devices = parsePactlSources(sources);

    expect(devices, hasLength(1));
    expect(devices.single.label, isNot(startsWith('Monitor of')));
  });

  test('keeps colons in the label', () {
    final devices = parsePactlSources(sources);

    expect(devices.single.label, 'Blue Microphones: Analog Stereo');
  });

  test('reads the sample rate', () {
    final devices = parsePactlSources(sources);

    expect(devices.single.sampleRates, [44100]);
  });

  test('returns nothing for empty output', () {
    expect(parsePactlSources(const []), isEmpty);
  });
}
