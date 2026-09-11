/// `PlatformException` code native platforms send for [RecordResumeNoDeviceException].
const noInputDeviceErrorCode = 'no_input_device';

/// `resume()` throws this when the original input device is gone and no other
/// one is available.
///
/// The recording stays paused; call `resume()` again once a device is available.
class RecordResumeNoDeviceException implements Exception {
  const RecordResumeNoDeviceException([
    this.message = 'No input device available to resume recording.',
  ]);

  /// Describes why the recorder could not resume.
  final String message;

  @override
  String toString() => 'RecordResumeNoDeviceException: $message';
}
