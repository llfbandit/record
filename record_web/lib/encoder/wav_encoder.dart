import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'encoder.dart';

// Assumes bit depth to int16
class WavEncoder implements Encoder {
  final int sampleRate;
  final int numChannels;
  Uint8List _audioData = Uint8List(0);

  WavEncoder({required this.sampleRate, required this.numChannels});

  @override
  void encode(Int16List buffer) {
    _audioData = Uint8List.fromList(_audioData + buffer.buffer.asUint8List());
  }

  @override
  web.Blob finish() {
    final headerSize = 44;
    final bitsPerSample = 16;
    final bytesPerSample = (bitsPerSample / 8).toInt();
    final byteRate = sampleRate * numChannels * bytesPerSample;
    final blockAlign = numChannels * bytesPerSample;

    final view = ByteData(headerSize);

    // RIFF chunk
    view.setString(0, 'RIFF');
    view.setUint32(4, headerSize + _audioData.length - 8, Endian.little);
    view.setString(8, 'WAVE');

    view.setString(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, numChannels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, byteRate, Endian.little);
    view.setUint16(32, blockAlign, Endian.little);
    view.setUint16(34, bitsPerSample, Endian.little);

    view.setString(36, 'data');
    view.setUint32(40, _audioData.length, Endian.little);

    _audioData = Uint8List.fromList(view.buffer.asUint8List() + _audioData);

    final blob = web.Blob(<JSUint8Array>[_audioData.toJS].toJS,
        web.BlobPropertyBag(type: 'audio/wav'));

    cleanup();

    return blob;
  }

  @override
  void cleanup() => _audioData = Uint8List(0);
}

extension ByteDataExt on ByteData {
  void setString(int offset, String str) {
    final len = str.length;

    for (var i = 0; i < len; ++i) {
      setUint8(offset + i, str.codeUnitAt(i));
    }
  }
}
