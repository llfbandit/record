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

  /// Set the speakerphone on.
  /// If [true], this will set the speakerphone on.
  /// Useful on devices with echo cancellation issues.
  final bool setSpeakerphoneOn;

  /// Defines the audio source.
  /// An audio source defines both a default physical source of audio signal, and a recording configuration.
  ///
  /// Depending of the constructor some effects are available or not depending of this source.
  ///
  /// Most of the time, you should use [AndroidAudioSource.defaultSource] or [AndroidAudioSource.mic].
  final AndroidAudioSource audioSource;

  /// Defines the audio manager mode.
  /// This is used to set the audio manager mode before recording.
  ///
  /// Switching to [AudioManagerMode.modeInCommunication] can help to resolve
  /// acoustic echo cancellation issues on some devices (Tested on Samsung S20).
  ///
  /// Defaults to [AudioManagerMode.modeNormal].
  final AudioManagerMode audioManagerMode;

  const AndroidRecordConfig({
    this.useLegacy = false,
    this.muteAudio = false,
    this.manageBluetooth = true,
    this.setSpeakerphoneOn = false,
    this.audioSource = AndroidAudioSource.defaultSource,
    this.audioManagerMode = AudioManagerMode.modeNormal,
  });

  Map<String, dynamic> toMap() {
    return {
      'useLegacy': useLegacy,
      'muteAudio': muteAudio,
      'manageBluetooth': manageBluetooth,
      'setSpeakerphoneOn': setSpeakerphoneOn,
      'audioSource': audioSource.name,
      'audioManagerMode': audioManagerMode.name,
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

/// Constants for Android for setting specific audio manager modes
/// https://developer.android.com/reference/kotlin/android/media/AudioManager#setmode
enum AudioManagerMode {
  modeNormal,
  modeRingtone,
  modeInCall,
  modeInCommunication,
  modeCallScreening,
  modeCallRedirect,
  modeCommunicationRedirect,
}
