import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// Tracks the loudness of the captured PCM stream.
class AmplitudeTracker {
  static const _silence = -160.0;

  double _current = _silence;
  double _max = _silence;

  Amplitude get amplitude => Amplitude(current: _current, max: _max);

  void reset() {
    _current = _silence;
    _max = _silence;
  }

  /// Reads the loudest sample of s16le [data] as dBFS.
  void update(Uint8List data) {
    if (data.isEmpty) return;

    double maxSample = 0;
    for (int i = 0; i < data.length - 1; i += 2) {
      int sample = data[i] | (data[i + 1] << 8);
      if (sample > 32767) sample -= 65536;

      final absSample = sample.abs().toDouble();
      if (absSample > maxSample) {
        maxSample = absSample;
      }
    }

    _current = maxSample > 0
        ? 20 * (log(maxSample / 32767.0) / ln10)
        : _silence;

    if (_current > _max) {
      _max = _current;
    }
  }
}
