/// Constants that specify optional audio behaviors.
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
