@JS('self')
@staticInterop
library webaudio;

import 'dart:html';
import 'dart:typed_data';

import 'package:js/js.dart';

@JS()
@staticInterop
class AudioContext {
  external factory AudioContext();
}

extension AudioContextExt on AudioContext {
  external MediaStreamAudioSourceNode createMediaStreamSource(
      MediaStream stream);

  external AnalyserNode createAnalyser();

  external close();

  external resume();

  external suspend();

  external String get state;
}

@JS()
@staticInterop
class MediaStreamAudioSourceNode {
  external factory MediaStreamAudioSourceNode(
      AudioContext context, MediaStream stream);
}

extension MediaStreamAudioSourceNodeExt on MediaStreamAudioSourceNode {
  external dynamic connect(dynamic destination);
}

@JS()
@staticInterop
class AnalyserNode {
  external factory AnalyserNode(AudioContext context);
}

extension AnalyserNodeExt on AnalyserNode {
  external dynamic connect(dynamic destination);

  external num get minDecibels;
  external set minDecibels(num value);

  external num get maxDecibels;
  external set maxDecibels(num value);

  external num get fftSize;
  external set fftSize(num value);

  external num get frequencyBinCount;
  external getFloatFrequencyData(Float32List array);
}
