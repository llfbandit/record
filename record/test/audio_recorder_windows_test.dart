import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

class _FakePlatform extends RecordPlatform {
  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> start(String recorderId, RecordConfig config,
      {required String path}) async {}

  @override
  Future<Stream<Uint8List>> startStream(
          String recorderId, RecordConfig config) async =>
      const Stream<Uint8List>.empty();

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}

  @override
  Future<String?> stop(String recorderId) async => null;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Future<bool> isRecording(String recorderId) async => false;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late RecordPlatform original;

  setUp(() {
    original = RecordPlatform.instance;
    RecordPlatform.instance = _FakePlatform();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    RecordPlatform.instance = original;
  });

  const win = WindowsRecordConfig(captureSystemAudio: true);

  test('file: aacLc is rejected', () {
    final r = AudioRecorder();
    expect(
      r.start(const RecordConfig(windowsConfig: win), path: 'a.wav'),
      throwsArgumentError,
    );
  });

  test('file: wav is accepted', () async {
    final r = AudioRecorder();
    await r.start(
      const RecordConfig(encoder: AudioEncoder.wav, windowsConfig: win),
      path: 'a.wav',
    );
  });

  test('stream: wav is rejected, pcm16bits accepted', () async {
    final r = AudioRecorder();
    expect(
      r.startStream(
          const RecordConfig(encoder: AudioEncoder.wav, windowsConfig: win)),
      throwsArgumentError,
    );
    await r.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits, windowsConfig: win));
  });

  test('other platforms ignore the flag', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final r = AudioRecorder();
    await r.start(const RecordConfig(windowsConfig: win), path: 'a.m4a');
  });

  test('toMap contains windowsConfig', () {
    final m = const RecordConfig(
      windowsConfig: WindowsRecordConfig(
          captureSystemAudio: true, micGain: 1.5, systemAudioGain: 0.3),
    ).toMap();
    expect(m['windowsConfig'], {
      'captureSystemAudio': true,
      'micGain': 1.5,
      'systemAudioGain': 0.3,
    });
  });
}