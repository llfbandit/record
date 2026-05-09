part of '../record.dart';

/// Extension methods for conversions.
extension ConvertExt on AudioRecorder {
  /// Converts a [Uint8List] of bytes to a [List<int>] of signed 16-bit integers.
  ///
  /// [endian] specifies the byte order (default: [Endian.little]).
  /// Throws [ArgumentError] if `bytes.length` is not even.
  List<int> convertBytesToInt16(
    Uint8List bytes, [
    Endian endian = Endian.little,
  ]) {
    if (bytes.length % 2 != 0) {
      throw ArgumentError('Input byte length must be even.');
    }

    final byteData = ByteData.sublistView(bytes);
    final values = List<int>.filled(bytes.length ~/ 2, 0);

    for (var i = 0; i < values.length; i++) {
      values[i] = byteData.getInt16(i * 2, endian);
    }
    return values;
  }
}
