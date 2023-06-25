import 'dart:typed_data';

import 'package:record_web/js/js_interop/core.dart';

import 'encoder.dart';

// Assumes bit depth to int16
class WavEncoder implements Encoder {
  final int sampleRate;
  final int numChannels;
  int _numSamples = 0;
  // DataView(js) -> ByteData(dart)
  List<ByteData> _dataViews = [];

  WavEncoder({required this.sampleRate, required this.numChannels});

  @override
  void encode(Int16List buffer) {
    _dataViews.add(buffer.buffer.asByteData());
    _numSamples += buffer.length;
  }

  @override
  Blob finish() {
    final dataSize = numChannels * _numSamples * 2;
    final view = ByteData(44);

    view.setString(0, 'RIFF');
    view.setUint32(4, 36 + dataSize);
    view.setString(8, 'WAVE');
    view.setString(12, 'fmt ');
    view.setUint32(16, 16);
    view.setUint16(20, 1);
    view.setUint16(22, numChannels);
    view.setUint32(24, sampleRate);
    view.setUint32(28, sampleRate * 4);
    view.setUint16(32, numChannels * 2);
    view.setUint16(34, 16);
    view.setString(36, 'data');
    view.setUint32(40, dataSize);

    _dataViews.insert(0, view);

    final blob = Blob(_dataViews, BlobPropertyBag(type: 'audio/wav'));

    cleanup();

    return blob;
  }

  void setString(view, offset, str) {
    var len = str.length;
    for (var i = 0; i < len; ++i) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  }

  @override
  void cleanup() => _dataViews = [];
}

extension ByteDataExt on ByteData {
  void setString(offset, str) {
    var len = str.length;
    for (var i = 0; i < len; ++i) {
      setUint8(offset + i, str.charCodeAt(i));
    }
  }
}
