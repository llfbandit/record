import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

typedef OnStateChanged = void Function(RecordState state);

abstract class RecorderDelegate {
  Future<void> dispose();

  Future<Amplitude> getAmplitude();

  Future<bool> isPaused();

  Future<bool> isRecording();

  Future<void> pause();

  Future<void> resume();

  Future<void> start(RecordConfig config, {required String path});

  Future<Stream<Uint8List>> startStream(RecordConfig config);

  Future<String?> stop();
}
