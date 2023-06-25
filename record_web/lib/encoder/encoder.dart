import 'dart:typed_data';

import 'package:record_web/js/js_interop/core.dart';

abstract class Encoder {
  void encode(Int16List buffer);

  Blob finish();

  void cleanup();
}
