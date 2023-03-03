import 'dart:async';

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
  static final _token = Object();

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
  /// [path]: The output path file.
  /// If path is null, a temporary file will be created and thus auto-managed
  /// by the system to delete it when required.
  ///
  /// `web`: This parameter is ignored. Output path is retrieve on [stop]
  /// method is called.
  ///
  /// [encoder]: The audio encoder to be used for recording.
  ///
  /// [bitRate]: The audio encoding bit rate in bits per second.
  ///
  /// [samplingRate]: The sampling rate for audio in samples per second.
  /// Ignored on web platform.
  ///
  /// [numChannels]: The numbers of channels for the recording.
  /// 1 = mono, 2 = stereo, etc.
  ///
  /// [device]: The device to be used for recording. If null, default device
  /// will be selected.
  Future<void> start({
    String? path,
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
    int numChannels = 2,
    InputDevice? device,
  });

  /// Same as [start] with output stream instead of a path.
  ///
  /// Where possible, the underlying platform won't generate a file.
  /// Otherwise, a temporary file will be created and thus auto-managed
  /// by the system to delete it when required.
  ///
  /// When stopping the record, you must rely on stream close event to get
  /// full recorded data.
  Future<Stream<List<int>>> startStream({
    AudioEncoder encoder = AudioEncoder.aacLc,
    int bitRate = 128000,
    int samplingRate = 44100,
    int numChannels = 2,
    InputDevice? device,
  }) =>
      throw UnimplementedError(
          'startStream not implemented on the current platform.');

  /// Stops recording session and release internal recorder resource.
  ///
  /// Returns the output path.
  Future<String?> stop();

  /// Pauses recording session.
  ///
  /// Note `Android`: Usable on API >= 24(Nougat). Does nothing otherwise.
  Future<void> pause();

  /// Resumes recording session after [pause].
  ///
  /// Note `Android`: Usable on API >= 24(Nougat). Does nothing otherwise.
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

  /// Gets current average & max amplitudes (dBFS)
  /// Always returns zeros on unsupported platforms
  Future<Amplitude> getAmplitude();

  /// Checks if the given encoder is supported on the current platform.
  Future<bool> isEncoderSupported(AudioEncoder encoder);

  /// Lists capture/input devices available on the platform.
  ///
  /// On Android and iOS, an empty list will be returned.
  ///
  /// On web, and in general, you should already have permission before
  /// accessing this method otherwise the list may return an empty list.
  Future<List<InputDevice>> listInputDevices();

  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  Stream<RecordState> onStateChanged() => throw UnimplementedError(
      'onStateChanged not implemented on the current platform.');
}
