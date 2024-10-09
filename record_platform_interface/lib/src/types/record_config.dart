import 'package:record_platform_interface/src/types/types.dart';

/// Recording configuration
///
/// `encoder`: The audio encoder to be used for recording.
///
/// `bitRate`*: The audio encoding bit rate in bits per second.
///
/// `sampleRate`*: The sample rate for audio in samples per second.
///
/// `numChannels`: The numbers of channels for the recording.
/// 1 = mono, 2 = stereo.
///
/// `device`: The device to be used for recording. If null, default device
/// will be selected.
///
/// `autoGain`*: The recorder will try to auto adjust recording volume in a limited range.
///
/// `echoCancel`*: The recorder will try to reduce echo.
///
/// `noiseSuppress`*: The recorder will try to negates the input noise.
///
/// `*`: May not be considered on all platforms/formats.
class RecordConfig {
  /// The requested output format through this given encoder.
  final AudioEncoder encoder;

  /// The audio encoding bit rate in bits per second if applicable.
  final int bitRate;

  /// The sample rate for audio in samples per second if applicable.
  final int sampleRate;

  /// The numbers of channels for the recording. 1 = mono, 2 = stereo.
  /// Most platforms only accept 2 at most.
  final int numChannels;

  /// The device to be used for recording. If null, default device
  /// will be selected.
  final InputDevice? device;

  /// The recorder will try to auto adjust recording volume in a limited range.
  final bool autoGain;

  /// The recorder will try to reduce echo.
  final bool echoCancel;

  /// The recorder will try to negates the input noise.
  final bool noiseSuppress;

  /// Android specific configuration.
  final AndroidRecordConfig androidConfig;

  /// iOS specific audioCategories
  final IosRecordConfig iosConfig;

  const RecordConfig({
    this.encoder = AudioEncoder.aacLc,
    this.bitRate = 128000,
    this.sampleRate = 44100,
    this.numChannels = 2,
    this.device,
    this.autoGain = false,
    this.echoCancel = false,
    this.noiseSuppress = false,
    this.androidConfig = const AndroidRecordConfig(),
    this.iosConfig = const IosRecordConfig(),
  });

  Map<String, dynamic> toMap() {
    return {
      'encoder': encoder.name,
      'bitRate': bitRate,
      'sampleRate': sampleRate,
      'numChannels': numChannels,
      'device': device?.toMap(),
      'autoGain': autoGain,
      'echoCancel': echoCancel,
      'noiseSuppress': noiseSuppress,
      'androidConfig': androidConfig.toMap(),
      'iosConfig': iosConfig.toMap(),
    };
  }
}

/// Android specific configuration for recording.
class AndroidRecordConfig {
  /// Uses Android MediaRecorder if [true].
  ///
  /// Uses advanced recorder with media codecs and additionnal features
  /// by default.
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

  // Defines the audio source.
  // An audio source defines both a default physical source of audio signal, and a recording configuration.
  // Default is VOICE_COMMUNICATION
  final AndroidAudioSource androidAudioSource;
  /// Try to start a bluetooth audio connection to a headset.
  /// Defaults to [true].
  final bool manageBluetoothAudio;

  const AndroidRecordConfig({
    this.useLegacy = false,
    this.muteAudio = false,
    this.androidAudioSource = AndroidAudioSource.defaultSource,
    this.manageBluetoothAudio = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'useLegacy': useLegacy,
      'muteAudio': muteAudio,
      'androidAudioSource': androidAudioSource.index,
      'manageBluetoothAudio': manageBluetoothAudio,
    };
  }
}

/// iOS specific configuration for recording.
class IosRecordConfig {
  /// Constants that specify optional audio behaviors.
  /// https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions
  final List<IosAudioCategoryOption> categoryOptions;
  /// Manage the shared AVAudioSession (defaults to `true`).
  /// Set this to false if another plugin is already managing the AVAudioSession.
  /// If false, audioCategories config will have no effect.
  final bool manageAudioSession;

  const IosRecordConfig({
    this.categoryOptions = const [
      IosAudioCategoryOption.defaultToSpeaker,
      IosAudioCategoryOption.allowBluetooth,
      IosAudioCategoryOption.allowBluetoothA2DP,
    ],
    this.manageAudioSession = true,
  });
  Map<String, dynamic> toMap() {
    return {
      "categoryOptions": categoryOptions.map((e) => e.name).join(','),
      "manageAudioSession": manageAudioSession,
    };
  }
}
