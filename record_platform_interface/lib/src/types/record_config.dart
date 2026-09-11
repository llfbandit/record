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
  ///
  /// On iOS and macOS, this also turns on echo cancellation.
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

  /// What the recorder does when the input device in use goes away
  /// (e.g. headset unplugged, Bluetooth/USB mic disconnected).
  ///
  /// Defaults to [AudioRouteChangeMode.pause], like [audioInterruption], so the
  /// app keeps the recording and decides when to resume.
  ///
  /// Platforms: Android, iOS, macOS web & Windows.
  /// Android's legacy recorder needs API 28.
  final AudioRouteChangeMode audioRouteChange;

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
    this.audioRouteChange = AudioRouteChangeMode.pause,
    this.streamBufferSize,
  });

  RecordConfig copyWith({
    AudioEncoder? encoder,
    int? bitRate,
    int? sampleRate,
    int? numChannels,
    ({InputDevice? value})? device,
    bool? autoGain,
    bool? echoCancel,
    bool? noiseSuppress,
    AndroidRecordConfig? androidConfig,
    IosRecordConfig? iosConfig,
    AudioInterruptionMode? audioInterruption,
    AudioRouteChangeMode? audioRouteChange,
    ({int? value})? streamBufferSize,
  }) {
    return RecordConfig(
      encoder: encoder ?? this.encoder,
      bitRate: bitRate ?? this.bitRate,
      sampleRate: sampleRate ?? this.sampleRate,
      numChannels: numChannels ?? this.numChannels,
      device: device != null ? device.value : this.device,
      autoGain: autoGain ?? this.autoGain,
      echoCancel: echoCancel ?? this.echoCancel,
      noiseSuppress: noiseSuppress ?? this.noiseSuppress,
      androidConfig: androidConfig ?? this.androidConfig,
      iosConfig: iosConfig ?? this.iosConfig,
      audioInterruption: audioInterruption ?? this.audioInterruption,
      audioRouteChange: audioRouteChange ?? this.audioRouteChange,
      streamBufferSize: streamBufferSize != null
          ? streamBufferSize.value
          : this.streamBufferSize,
    );
  }

  factory RecordConfig.fromMap(Map map) {
    return RecordConfig(
      encoder: AudioEncoder.values.firstWhere(
        (e) => e.name == map['encoder'],
        orElse: () => AudioEncoder.aacLc,
      ),
      bitRate: map['bitRate'] as int? ?? 128000,
      sampleRate: map['sampleRate'] as int? ?? 44100,
      numChannels: map['numChannels'] as int? ?? 2,
      device: map['device'] != null
          ? InputDevice.fromMap(map['device'] as Map)
          : null,
      autoGain: map['autoGain'] as bool? ?? false,
      echoCancel: map['echoCancel'] as bool? ?? false,
      noiseSuppress: map['noiseSuppress'] as bool? ?? false,
      audioInterruption:
          AudioInterruptionMode.values[map['audioInterruption'] as int? ??
              AudioInterruptionMode.pause.index],
      audioRouteChange:
          AudioRouteChangeMode.values[map['audioRouteChange'] as int? ??
              AudioRouteChangeMode.pause.index],
      streamBufferSize: map['streamBufferSize'] as int?,
    );
  }

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
      'audioRouteChange': audioRouteChange.index,
      'streamBufferSize': streamBufferSize,
    };
  }

  @override
  String toString() {
    return 'RecordConfig(\n'
        '  encoder: $encoder,\n'
        '  bitRate: $bitRate,\n'
        '  sampleRate: $sampleRate,\n'
        '  numChannels: $numChannels,\n'
        '  device: $device,\n'
        '  autoGain: $autoGain,\n'
        '  echoCancel: $echoCancel,\n'
        '  noiseSuppress: $noiseSuppress,\n'
        '  audioInterruption: $audioInterruption,\n'
        '  audioRouteChange: $audioRouteChange,\n'
        '  streamBufferSize: $streamBufferSize,\n'
        ')';
  }
}
