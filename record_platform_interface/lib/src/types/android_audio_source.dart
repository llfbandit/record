// Constants for Android for setting specific audio source types
// https://developer.android.com/reference/kotlin/android/media/MediaRecorder.AudioSource
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
