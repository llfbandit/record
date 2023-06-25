import 'dart:typed_data';

import 'package:record_web/js/js_interop/core.dart';

import 'encoder.dart';

class PcmEncoder implements Encoder {
  // DataView(js) -> ByteData(dart)
  List<ByteData> _dataViews = [];

  @override
  void encode(Int16List buffer) {
    _dataViews.add(buffer.buffer.asByteData());
  }

  @override
  Blob finish() {
    final blob = Blob(_dataViews, BlobPropertyBag(type: 'audio/pcm'));

    cleanup();

    return blob;
  }

  @override
  void cleanup() => _dataViews = [];
}
