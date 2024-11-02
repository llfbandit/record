/// Android specific configuration for recording.
class AndroidRecordConfig {
  /// Uses Android MediaRecorder if [true].
  ///
  /// Uses advanced recorder with media codecs and additionnal features
  /// by default.
  ///
  /// While advanced recorder unlocks additionnal features, legacy recorder
  /// is stability oriented.
  final bool useLegacy;

  /// If [true], this will mute all audio streams like alarms, music, ring, ...
  ///
  /// This is useful when you want to record audio without any background noise.
  ///
  /// The streams are restored to their previous state after recording is stopped
  /// and will stay at current state on pause/resume.
  ///
  /// Use at your own risks!
  final bool muteAudio;

  /// Try to start a bluetooth audio connection to a headset (Bluetooth SCO).
  ///
  /// Defaults to [true].
  final bool manageBluetooth;

  /// Defines the audio source.
  /// An audio source defines both a default physical source of audio signal, and a recording configuration.
  ///
  /// Depending of the constructor some effects are available or not depending of this source.
  ///
  /// Most of the time, you should use [AndroidAudioSource.defaultSource] or [AndroidAudioSource.mic].
  final AndroidAudioSource audioSource;

  const AndroidRecordConfig({
    this.useLegacy = false,
    this.muteAudio = false,
    this.manageBluetooth = true,
    this.audioSource = AndroidAudioSource.defaultSource,
  });

  Map<String, dynamic> toMap() {
    return {
      'useLegacy': useLegacy,
      'muteAudio': muteAudio,
      'manageBluetooth': manageBluetooth,
      'audioSource': audioSource.name,
    };
  }
}

/// Constants for Android for setting specific audio source types
/// https://developer.android.com/reference/kotlin/android/media/MediaRecorder.AudioSource
enum AndroidAudioSource {
  defaultSource,
  mic,
  voiceUplink,
  voiceDownlink,
  voiceCall,
  camcorder,
  voiceRecognition,
  voiceCommunication,
  remoteSubMix,
  unprocessed,
  voicePerformance,
}
