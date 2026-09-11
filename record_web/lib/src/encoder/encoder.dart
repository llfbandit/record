import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Turns captured PCM samples into a recording [web.Blob].
abstract class Encoder {
  void encode(Int16List buffer);

  web.Blob finish();

  void cleanup();
}

/// Keeps audio in a browser-owned [web.Blob] rather than the Dart heap.
class BlobAccumulator {
  // Batches many chunks per fold while keeping the heap light.
  static const _foldThreshold = 1024 * 1024;

  web.Blob? _blob;
  final List<JSUint8Array> _pending = [];
  int _pendingLength = 0;
  int _length = 0;

  /// Bytes added since the last [clear].
  int get length => _length;

  void add(Uint8List bytes) {
    _pending.add(bytes.toJS);
    _pendingLength += bytes.length;
    _length += bytes.length;

    if (_pendingLength >= _foldThreshold) {
      _blob = _build();
      _pending.clear();
      _pendingLength = 0;
    }
  }

  /// Everything added, prefixed by [header] if given.
  web.Blob toBlob(String type, {Uint8List? header}) {
    return _build(
      options: web.BlobPropertyBag(type: type),
      header: header,
    );
  }

  void clear() {
    _blob = null;
    _pending.clear();
    _pendingLength = 0;
    _length = 0;
  }

  web.Blob _build({web.BlobPropertyBag? options, Uint8List? header}) {
    final parts = <JSAny>[?header?.toJS, ?_blob, ..._pending].toJS;
    return options == null ? web.Blob(parts) : web.Blob(parts, options);
  }
}
