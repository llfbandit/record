import 'dart:typed_data';
import 'package:web/web.dart' as web;

abstract class Encoder {
  void encode(Int16List buffer);

  web.Blob finish();

  void cleanup();
}
