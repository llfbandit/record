/// Recorder behaviour when audio is interrupted by another source.
enum AudioInterruptionMode {
  /// Recording state stays the same on interruption.
  none,

  /// Pauses automatically, resumes manually the recording.
  pause,

  /// Pauses and resumes automatically the recording.
  pauseResume,
}
