import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'dart:js_interop';

import 'encoder.dart';

class PcmEncoder implements Encoder {
  List<int> _dataViews = []; // Uint8List

  @override
  void encode(Int16List buffer) {
    _dataViews.addAll(buffer.buffer.asUint8List());
  }

  @override
  web.Blob finish() {
    final blob = web.Blob(
      <JSUint8Array>[Uint8List.fromList(_dataViews).toJS].toJS,
      web.BlobPropertyBag(type: 'audio/pcm'),
    );

    cleanup();

    return blob;
  }

  @override
  void cleanup() => _dataViews = [];
}
