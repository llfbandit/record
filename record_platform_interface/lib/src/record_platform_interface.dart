import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'record_platform.dart';
import 'types/types.dart';

/// Record platform interface
abstract class RecordPlatform extends PlatformInterface
    implements
        RecordMethodChannelPlatformInterface,
        RecordEventChannelPlatformInterface {
  /// Constructs a RecordPlatformInterface.
  RecordPlatform() : super(token: _token);

  static final Object _token = Object();

  /// The default instance of [RecordPlatform] to use.
  ///
  /// Defaults to [RecordPlatformImpl].
  static RecordPlatform instance = RecordPlatformImpl();

  @override
  RecordIos? getIos(String recorderId) => null;
}

/// Record method channel platform interface
abstract class RecordMethodChannelPlatformInterface {
  /// Create a recorder
  Future<void> create(String recorderId);

  /// Starts new recording session.
  ///
  /// [path]: The output path file. Required on all IO platforms.
  /// On `web`: This parameter is ignored.
  ///
  /// Output path can be retrieves when [stop] method is called.
  Future<void> start(String recorderId, RecordConfig config,
      {required String path});

  /// Same as [start] with output stream instead of a path.
  ///
  /// When stopping the record, you must rely on stream close event to get
  /// full recorded data.
  Future<Stream<Uint8List>> startStream(String recorderId, RecordConfig config);

  /// Stops recording session and release internal recorder resource.
  ///
  /// Returns the output path.
  Future<String?> stop(String recorderId);

  /// Pauses recording session.
  ///
  /// Note `Android`: Usable on API >= 24(Nougat). Does nothing otherwise.
  Future<void> pause(String recorderId);

  /// Resumes recording session after [pause].
  ///
  /// Note `Android`: Usable on API >= 24(Nougat). Does nothing otherwise.
  Future<void> resume(String recorderId);

  /// Checks if there's valid recording session.
  /// So if session is paused, this method will still return [true].
  Future<bool> isRecording(String recorderId);

  /// Checks if recording session is paused.
  Future<bool> isPaused(String recorderId);

  /// Checks and optionally requests for audio record permission.
  ///
  /// The [request] parameter controls whether to request permission if not
  /// already granted. Defaults to `true`.
  Future<bool> hasPermission(String recorderId, {bool request = true});

  /// Dispose the recorder
  Future<void> dispose(String recorderId);

  /// Gets current average & max amplitudes (dBFS)
  /// Always returns zeros on unsupported platforms
  Future<Amplitude> getAmplitude(String recorderId);

  /// Checks if the given encoder is supported on the current platform.
  Future<bool> isEncoderSupported(String recorderId, AudioEncoder encoder);

  /// Lists capture/input devices available on the platform.
  ///
  /// On Android and iOS, an empty list will be returned.
  ///
  /// On web, and in general, you should already have permission before
  /// accessing this method otherwise the list may return an empty list.
  Future<List<InputDevice>> listInputDevices(String recorderId);

  /// Stops the recording if needed and remove current file.
  Future<void> cancel(String recorderId);

  /// iOS platform specific methods.
  ///
  /// Returns [null] when not on iOS platform.
  RecordIos? getIos(String recorderId);
}

/// Record event channel platform interface
abstract class RecordEventChannelPlatformInterface {
  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  Stream<RecordState> onStateChanged(String recorderId);
}

/// iOS platform specific methods.
abstract class RecordIos {
  /// Activates or deactivates the management of iOS audio session.
  ///
  /// If `true`, the plugin will activate session and setup categories for you.
  /// This may conflicts with current settings in your app if you already have external audio session management.
  ///
  /// If `false`, the audio session won't be activated and categories will stay the same.
  /// Other parameters may be touched for recording requirements (interruption, sample rate, channels, ...).
  ///
  /// In both cases, usage of [setAudioSessionActive] and [setAudioSessionCategory] is allowed.
  Future<void> manageAudioSession(bool manage);

  /// Activates or deactivates your app’s audio session.
  Future<void> setAudioSessionActive(bool active);

  /// Sets the audio session’s category with the specified options.
  Future<void> setAudioSessionCategory({
    IosAudioCategory category = IosAudioCategory.playAndRecord,
    List<IosAudioCategoryOptions> options = const [
      IosAudioCategoryOptions.duckOthers,
      IosAudioCategoryOptions.defaultToSpeaker,
      IosAudioCategoryOptions.allowBluetooth,
      IosAudioCategoryOptions.allowBluetoothA2DP,
    ],
  });
}
