import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record_platform_interface/src/method_channel_record.dart';
import 'package:record_platform_interface/src/types/types.dart';

/// The interface that implementations of Record must implement.
///
/// Platform implementations should extend this class rather than implement it
/// as record does not consider newly added methods to be breaking changes.
/// Extending this class ensures that the subclass will get the default
/// implementation, while platform implementations that merely implement the
/// interface will be broken by newly added [RecordPlatform] functions.
abstract class RecordPlatform extends PlatformInterface {
  /// A token used for verification of subclasses to ensure they extend this
  /// class instead of implementing it.
  static const _token = Object();

  /// Constructs a [RecordPlatform].
  RecordPlatform() : super(token: _token);

  static RecordPlatform _instance = MethodChannelRecord();

  /// The default instance of [RecordPlatform] to use.
  ///
  /// Defaults to [MethodChannelRecord].
  static RecordPlatform get instance => _instance;

  /// Platform-specific plugins should set this to an instance of their own
  /// platform-specific class that extends [RecordPlatform] when they register
  /// themselves.
  static set instance(RecordPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Starts new recording session.
  ///
  /// [path]: The output path file. If not provided will use temp folder.
  /// Ignored on web platform, output path is retrieve on stop.
  ///
  /// [encoder]: The audio encoder to be used for recording.
  /// Ignored on web platform.
  ///
  /// [bitRate]: The audio encoding bit rate in bits per second.
  ///
  /// [samplingRate]: The sampling rate for audio in samples per second.
  /// Ignored on web platform.
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.AAC,
    int bitRate = 128000,
    double samplingRate = 44100.0,
  });

  /// Stops recording session and release internal recorder resource.
  /// Returns the output path.
  Future<String?> stop();

  /// Pauses recording session.
  ///
  /// Note: Usable on Android API >= 24(Nougat). Does nothing otherwise.
  Future<void> pause();

  /// Resumes recording session after [pause].
  ///
  /// Note: Usable on Android API >= 24(Nougat). Does nothing otherwise.
  Future<void> resume();

  /// Checks if there's valid recording session.
  /// So if session is paused, this method will still return [true].
  Future<bool> isRecording();

  /// Checks if recording session is paused.
  Future<bool> isPaused();

  /// Checks and requests for audio record permission.
  Future<bool> hasPermission();

  /// Dispose the recorder
  Future<void> dispose();

  /// Gets current average & max amplitudes
  /// Always returns zeros on web platform
  Future<Amplitude> getAmplitude();
}
