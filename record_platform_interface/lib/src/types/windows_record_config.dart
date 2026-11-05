/// Windows specific configuration.
class WindowsRecordConfig {
  /// Mix system audio (WASAPI loopback) with the microphone.
  /// Only WAV / pcm16bits encoders are supported for now.
  final bool captureSystemAudio;
  final double micGain;
  final double systemAudioGain;

  const WindowsRecordConfig({
    this.captureSystemAudio = false,
    this.micGain = 1.0,
    this.systemAudioGain = 0.7,
  });

  Map<String, dynamic> toMap() => {
        'captureSystemAudio': captureSystemAudio,
        'micGain': micGain,
        'systemAudioGain': systemAudioGain,
      };
}