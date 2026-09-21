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

  test('skips a monitor the description does not name as one', () {
    final devices = parsePactlSources(const [
      'Source #0',
      '\tDescription: Built-in Audio Analog Stereo',
      '\t\tnode.name = "alsa_output.pci-0000_00_1f.3.analog-stereo.monitor"',
    ]);

    expect(devices, isEmpty);
  });

  test('strips the quotes pactl puts around the id', () {
    final devices = parsePactlSources(sources);

    expect(
      devices.single.id,
      'alsa_input.usb-Blue_Microphones-00.analog-stereo',
    );
  });

  test('keeps an equals sign inside the id', () {
    final devices = parsePactlSources(const [
      'Source #0',
      '\tDescription: Headset',
      '\t\tnode.name = "bluez_input.00:11:22=33"',
    ]);

    expect(devices.single.id, 'bluez_input.00:11:22=33');
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
