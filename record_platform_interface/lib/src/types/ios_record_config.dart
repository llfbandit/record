/// iOS specific configuration for recording.
class IosRecordConfig {
  /// Constants that specify optional audio behaviors.
  ///
  /// https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions
  final List<IosAudioCategoryOption> categoryOptions;

  /// Manage the shared AVAudioSession (defaults to `true`).
  ///
  /// Set this to `false` if another plugin is already managing the AVAudioSession.
  ///
  /// If `false`, there will be no check of the [RecordConfig] given.
  final bool manageAudioSession;

  /// Whether haptics and system sounds (including incoming call ring tones) are
  /// allowed to play while recording (defaults to `false`).
  ///
  /// When `true`, the recording session is not interrupted by an incoming call
  /// ringing. The interruption only begins once the user actually answers the
  /// call. This maps to
  /// `AVAudioSession.setAllowHapticsAndSystemSoundsDuringRecording(_:)`.
  ///
  /// https://developer.apple.com/documentation/avfaudio/avaudiosession/setallowhapticsandsystemsoundsduringrecording(_:)
  final bool allowHapticsAndSystemSoundsDuringRecording;

  const IosRecordConfig({
    this.categoryOptions = const [
      IosAudioCategoryOption.defaultToSpeaker,
      IosAudioCategoryOption.allowBluetooth,
      IosAudioCategoryOption.allowBluetoothA2DP,
    ],
    @Deprecated('Use AudioRecorder.ios.manageAudioSession instead.')
    this.manageAudioSession = true,
    this.allowHapticsAndSystemSoundsDuringRecording = false,
  });
  Map<String, dynamic> toMap() {
    return {
      "categoryOptions": categoryOptions.map((e) => e.name).join(','),
      "manageAudioSession": manageAudioSession,
      "allowHapticsAndSystemSoundsDuringRecording":
          allowHapticsAndSystemSoundsDuringRecording,
    };
  }
}

/// Constants that specify optional audio behaviors.
///
/// https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions
enum IosAudioCategoryOption {
  mixWithOthers,
  duckOthers,
  allowBluetooth,
  defaultToSpeaker,

  /// available from iOS 9.0
  interruptSpokenAudioAndMixWithOthers,

  /// available from iOS 10.0
  allowBluetoothA2DP,

  /// available from iOS 10.0
  allowAirPlay,

  /// available from iOS 14.5
  overrideMutedMicrophoneInterruption
}
