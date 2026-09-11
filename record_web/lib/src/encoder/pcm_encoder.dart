import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'encoder.dart';

class PcmEncoder implements Encoder {
  final _data = BlobAccumulator();

  @override
  void encode(Int16List buffer) {
    _data.add(
      buffer.buffer.asUint8List(buffer.offsetInBytes, buffer.lengthInBytes),
    );
  }

  @override
  web.Blob finish() {
    final blob = _data.toBlob('audio/pcm');

    cleanup();

    return blob;
  }

  @override
  void cleanup() => _data.clear();
}
