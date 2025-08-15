import 'types.dart';

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

  /// The recorder will try to auto adjust recording volume in a limited range (if available on the device).
  ///
  /// Recording volume may be lowered by using this.
  final bool autoGain;

  /// The recorder will try to reduce echo (if available on the device).
  ///
  /// Recording volume may be lowered by using this.
  final bool echoCancel;

  /// The recorder will try to negates the input noise (if available on the device).
  ///
  /// Recording volume may be lowered by using this.
  final bool noiseSuppress;

  /// Android specific configuration.
  final AndroidRecordConfig androidConfig;

  /// iOS specific configuration.
  final IosRecordConfig iosConfig;

  /// Recorder behaviour when audio is interrupted by another source.
  ///
  /// System alerts are ignored.
  /// Some other sources may not be detected (e.g. browser).
  ///
  /// Platforms: Android & iOS.
  final AudioInterruptionMode audioInterruption;

  /// Useful for those who need finer data when streaming.
  ///
  /// Underlying implementations may adjust to other value or throw exception if under miminum size required.
  ///
  /// Platforms: Android, iOS, macOS & web.
  final int? streamBufferSize;

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
    this.audioInterruption = AudioInterruptionMode.pause,
    this.streamBufferSize,
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
      'audioInterruption': audioInterruption.index,
      'streamBufferSize': streamBufferSize,
    };
  }
}
