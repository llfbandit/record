import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:record_platform_interface/record_platform_interface.dart';

/// The one device a machine without pactl can still record from: ALSA's
/// `default`, which is also what ffmpeg captures when no device is named.
const alsaDefaultInputDevice = InputDevice(
  id: 'default',
  label: 'Default input device',
);

/// Lists the input sources exposed by PulseAudio / PipeWire.
///
/// Falls back to [alsaDefaultInputDevice] where pactl cannot be run,
/// which is every machine with no PulseAudio or PipeWire server. Such a
/// machine can still record through [LinuxCaptureBackend.ffmpegAlsa], so
/// reporting no device at all would be wrong.
Future<List<InputDevice>> listPactlInputDevices() async {
  try {
    return parsePactlSources(await _runPactl(['list', 'sources']));
  } on ProcessException {
    return const [alsaDefaultInputDevice];
  }
}

/// Runs pactl and returns its output, one entry per line.
Future<List<String>> _runPactl(List<String> arguments) async {
  // LC_ALL=C keeps the output parseable under any user locale.
  final process = await Process.start(
    'pactl',
    arguments,
    environment: {'LC_ALL': 'C'},
  );

  // Read stderr too, or a full pipe blocks pactl.
  final stderrDone = process.stderr.drain<void>();

  final lines = await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();

  await stderrDone;
  await process.exitCode;

  return lines;
}

/// Reads a `key = "value"` property; parecord wants the value unquoted.
String _propertyValue(String line) {
  final value = line.substring(line.indexOf('=') + 1).trim();

  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }

  return value;
}

// Output can be retrieved with `pactl list sources`
// --- Example ---
// Source #2325
// State: SUSPENDED
// Name: alsa_output.usb-Generic_Blue_Microphones_LT_2201070607069D01069D_111000-00.analog-stereo.monitor
// Description: Monitor of Blue Microphones Analog Stereo
// Driver: PipeWire
// Sample Specification: s16le 2ch 48000Hz
// Channel Map: front-left,front-right
// Owner Module: 4294967295
// Mute: no
// Volume: front-left: 65536 / 100% / 0.00 dB,   front-right: 65536 / 100% / 0.00 dB
//         balance 0.00
// Base Volume: 65536 / 100% / 0.00 dB
// Monitor of Sink: alsa_output.usb-Generic_Blue_Microphones_LT_2201070607069D01069D_111000-00.analog-stereo
// Latency: 0 usec, configured 0 usec
// Flags: HARDWARE DECIBEL_VOLUME LATENCY
// Properties:
// 	alsa.card = "2"
// 	alsa.card_name = "Blue Microphones"
// 	alsa.class = "generic"
// 	alsa.components = "USB046d:0ab7"
//  node.name = "alsa_input.usb-Generic_Blue_Microphones_LT_2201070607069D01069D_111000-00.analog-stereo"
@visibleForTesting
List<InputDevice> parsePactlSources(List<String> output) {
  final devices = <InputDevice>[];
  String? currentDeviceId;
  String? currentDeviceName;
  List<int> currentSampleRates = [];

  void commitDevice() {
    if (currentDeviceId != null &&
        currentDeviceName != null &&
        !currentDeviceId.endsWith('.monitor') &&
        !currentDeviceName.startsWith('Monitor of')) {
      devices.add(
        InputDevice(
          id: currentDeviceId,
          label: currentDeviceName,
          sampleRates: currentSampleRates,
        ),
      );
    }
  }

  for (final line in output) {
    if (line.startsWith('Source #')) {
      commitDevice();
      currentDeviceId = null;
      currentDeviceName = null;
      currentSampleRates = [];
    } else if (line.trim().startsWith('node.name')) {
      currentDeviceId = _propertyValue(line);
    } else if (line.trim().startsWith('Name:')) {
      currentDeviceName = line.substring(line.indexOf(':') + 1).trim();
    } else if (line.trim().startsWith('Description:')) {
      currentDeviceName = line.substring(line.indexOf(':') + 1).trim();
    } else if (line.trim().startsWith('Sample Specification:')) {
      final match = RegExp(r'(\d+)Hz').firstMatch(line);
      if (match != null) {
        currentSampleRates = [int.parse(match.group(1)!)];
      }
    }
  }

  commitDevice();

  return devices;
}
