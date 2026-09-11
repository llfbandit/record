import 'exception/record_resume_exception.dart';

/// What the recorder does when the input device in use goes away.
enum AudioRouteChangeMode {
  /// Moves recording to the new default input device, with a minimal gap in
  /// the same file or stream.
  ///
  /// When the config named a device, `setOnConfigChanged` reports the move
  /// with a `null` device.
  ///
  /// With no other input device, it pauses instead, so `resume()` can retry.
  follow,

  /// Pauses the recording, so the user can plug their device back in before
  /// calling `resume()`.
  ///
  /// `resume()` goes back to the original device if it returned, or else
  ///  to the current default one, which `setOnConfigChanged`
  /// reports with a `null` device.
  ///
  /// With no device available, `resume()` throws
  /// [RecordResumeNoDeviceException] and the recording stays paused.
  pause,

  /// Stops and finalizes the recording.
  stop,
}
