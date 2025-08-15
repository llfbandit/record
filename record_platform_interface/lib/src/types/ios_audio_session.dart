/// iOS - Audio session category identifiers.
///
/// https://developer.apple.com/documentation/avfaudio/avaudiosession/category
enum IosAudioCategory {
  /// The category for an app in which sound playback is nonprimary — that is,
  /// your app also works with the sound turned off.
  ambient,

  /// The category for recording (input) and playback (output) of audio,
  /// such as for a Voice over Internet Protocol (VoIP) app.
  playAndRecord,

  /// The category for playing recorded music or other sounds
  /// that are central to the successful use of your app.
  playback,

  /// The category for recording audio while also silencing playback audio.
  record,

  /// The default audio session category.
  soloAmbient,
}

/// iOS - Constants that specify optional audio behaviors.
///
/// https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions
enum IosAudioCategoryOptions {
  /// An option that indicates whether audio from this session mixes with audio
  /// from active sessions in other audio apps.
  mixWithOthers,

  /// An option that reduces the volume of other audio sessions while audio
  /// from this session plays.
  duckOthers,

  /// An option that determines whether to pause spoken audio content
  /// from other sessions when your app plays its audio.
  interruptSpokenAudioAndMixWithOthers,

  /// An option that determines whether Bluetooth hands-free devices appear
  /// as available input routes.
  allowBluetooth,

  /// An option that determines whether you can stream audio from this session
  /// to Bluetooth devices that support the Advanced Audio Distribution Profile (A2DP).
  allowBluetoothA2DP,

  /// An option that determines whether you can stream audio
  /// from this session to AirPlay devices.
  allowAirPlay,

  /// An option that determines whether audio from the session
  /// defaults to the built-in speaker instead of the receiver.
  defaultToSpeaker,
}
