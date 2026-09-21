import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/amplitude_tracker.dart';

void main() {
  /// Builds s16le bytes from [samples].
  Uint8List pcm(List<int> samples) {
    final data = Uint8List(samples.length * 2);
    final view = ByteData.view(data.buffer);
    for (var i = 0; i < samples.length; i++) {
      view.setInt16(i * 2, samples[i], Endian.little);
    }
    return data;
  }

  test('starts silent', () {
    expect(AmplitudeTracker().amplitude.current, -160.0);
    expect(AmplitudeTracker().amplitude.max, -160.0);
  });

  test('reports 0 dBFS for a full scale sample', () {
    final tracker = AmplitudeTracker()..update(pcm([32767]));

    expect(tracker.amplitude.current, closeTo(0, 0.001));
  });

  test('reports silence for zero samples', () {
    final tracker = AmplitudeTracker()..update(pcm([0, 0]));

    expect(tracker.amplitude.current, -160.0);
  });

  test('keeps the loudest peak in max', () {
    final tracker = AmplitudeTracker()
      ..update(pcm([32767]))
      ..update(pcm([100]));

    expect(tracker.amplitude.current, lessThan(-40));
    expect(tracker.amplitude.max, closeTo(0, 0.001));
  });

  test('reads negative samples', () {
    final tracker = AmplitudeTracker()..update(pcm([-32767]));

    expect(tracker.amplitude.current, closeTo(0, 0.001));
  });

  test('ignores empty data', () {
    final tracker = AmplitudeTracker()
      ..update(pcm([32767]))
      ..update(Uint8List(0));

    expect(tracker.amplitude.current, closeTo(0, 0.001));
  });

  test('reset goes back to silence', () {
    final tracker = AmplitudeTracker()
      ..update(pcm([32767]))
      ..reset();

    expect(tracker.amplitude.current, -160.0);
    expect(tracker.amplitude.max, -160.0);
  });
}
