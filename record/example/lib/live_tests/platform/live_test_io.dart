import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

String get osVersion =>
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

// On macOS, the temporary directory is a folder of Caches that may not exist yet.
Future<String> tempPath(String name) async {
  final dir = await getTemporaryDirectory();
  await dir.create(recursive: true);
  return '${dir.path}/$name.wav';
}

// Seconds of audio in a WAV file: the data chunk size over the byte rate.
// Null when the file cannot tell.
Future<double?> wavSeconds(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;

  final bytes = await file.readAsBytes();
  if (bytes.length < 44) return null;

  final data = ByteData.sublistView(bytes);
  final byteRate = data.getUint32(28, Endian.little);
  if (byteRate == 0) return null;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    if (id == 'data') return size / byteRate;
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}
