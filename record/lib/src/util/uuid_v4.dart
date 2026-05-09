import 'dart:math';

/// A utility class for generating UUID v4.
class UuidV4 {
  static final _rnd = Random.secure();

  /// Generates a UUID v4.
  /// UUID v4 is a 128-bit identifier with random or pseudo-random numbers.
  static String generate() {
    final bytes = List<int>.generate(16, (_) => _rnd.nextInt(256));

    // Set the version (4) and variant (RFC 4122) bits
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // Variant RFC 4122

    // Convert to hexadecimal string
    final hexString =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

    // Format as UUID (8-4-4-4-12)
    final uuid = StringBuffer();
    uuid.write(hexString.substring(0, 8));
    uuid.write('-');
    uuid.write(hexString.substring(8, 12));
    uuid.write('-');
    uuid.write(hexString.substring(12, 16));
    uuid.write('-');
    uuid.write(hexString.substring(16, 20));
    uuid.write('-');
    uuid.write(hexString.substring(20, 32));

    return uuid.toString();
  }
}
