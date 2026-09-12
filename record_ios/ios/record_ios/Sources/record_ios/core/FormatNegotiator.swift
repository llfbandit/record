import AVFoundation

// Turns a config into output settings. Also tells what the hardware and the encoder accepted.
// https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers
enum FormatNegotiator {
  static func outputSettings(
    for config: RecordConfig,
    devices: DeviceRegistry
  ) throws -> (settings: [String: Any], effective: RecordConfig) {
    var settings = initialSettings(for: config)
    let deviceChannels = devices.inputChannelCount(for: config.device)

    adjustChannelCount(in: &settings, deviceChannels: deviceChannels)
    let channels = settings[AVNumberOfChannelsKey] as? Int ?? config.numChannels

    guard let inSettings = inputSettings(for: config, devices: devices, channels: channels),
          let inFormat = AVAudioFormat(settings: inSettings) else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Input format initialization failure."
      )
    }
    guard let outFormat = AVAudioFormat(settings: settings) else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Output format initialization failure."
      )
    }
    guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format conversion isn't possible. Format or configuration is not supported."
      )
    }

    adjustSampleRate(in: &settings, converter: converter)
    adjustBitRate(in: &settings, converter: converter)

    // If the encoder has no such key, we keep the value that was asked.
    let effective = config.negotiated(
      sampleRate: (settings[AVSampleRateKey] as? Double).map { Int($0) } ?? config.sampleRate,
      bitRate: settings[AVEncoderBitRateKey] as? Int ?? config.bitRate,
      numChannels: channels
    )

    return (settings, effective)
  }
}

// MARK: - Per-encoder initial settings

private extension FormatNegotiator {
  static func inputSettings(
    for config: RecordConfig,
    devices: DeviceRegistry,
    channels: Int
  ) -> [String: Any]? {
    AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: devices.inputSampleRate(for: config.device) ?? Double(config.sampleRate),
      channels: UInt32(max(1, channels)),
      interleaved: false
    )?.settings
  }

  static func initialSettings(for config: RecordConfig) -> [String: Any] {
    switch config.encoder {
    case AudioEncoder.aacLc.rawValue:  return aacSettings(formatId: kAudioFormatMPEG4AAC, config: config)
    case AudioEncoder.aacEld.rawValue: return aacSettings(formatId: kAudioFormatMPEG4AAC_ELD, config: config)
    case AudioEncoder.aacHe.rawValue:  return aacSettings(formatId: config.numChannels > 1 ? kAudioFormatMPEG4AAC_HE_V2 : kAudioFormatMPEG4AAC_HE, config: config)
    case AudioEncoder.amrNb.rawValue:  return amrNbSettings(config: config)
    case AudioEncoder.amrWb.rawValue:  return amrWbSettings(config: config)
    case AudioEncoder.opus.rawValue:   return opusSettings(config: config)
    case AudioEncoder.flac.rawValue:   return flacSettings(config: config)
    case AudioEncoder.pcm16bits.rawValue,
         AudioEncoder.wav.rawValue:    return pcmSettings(config: config)
    default:                           return aacSettings(formatId: kAudioFormatMPEG4AAC, config: config)
    }
  }

  static func aacSettings(formatId: UInt32, config: RecordConfig) -> [String: Any] {
    [
      AVFormatIDKey:            formatId,
      AVEncoderBitRateKey:      config.bitRate,
      AVSampleRateKey:          config.sampleRate,
      AVNumberOfChannelsKey:    config.numChannels,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
  }

  static func amrNbSettings(config: RecordConfig) -> [String: Any] {
    [
      AVFormatIDKey:            kAudioFormatAMR,
      AVEncoderBitRateKey:      config.bitRate,
      AVSampleRateKey:          8000,
      AVNumberOfChannelsKey:    1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
  }

  static func amrWbSettings(config: RecordConfig) -> [String: Any] {
    [
      AVFormatIDKey:            kAudioFormatAMR_WB,
      AVEncoderBitRateKey:      config.bitRate,
      AVSampleRateKey:          16000,
      AVNumberOfChannelsKey:    1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
  }

  static func opusSettings(config: RecordConfig) -> [String: Any] {
    [
      AVFormatIDKey:            kAudioFormatOpus,
      AVEncoderBitRateKey:      config.bitRate,
      AVSampleRateKey:          config.sampleRate,
      AVNumberOfChannelsKey:    config.numChannels,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
  }

  static func flacSettings(config: RecordConfig) -> [String: Any] {
    [
      AVFormatIDKey:            kAudioFormatFLAC,
      AVSampleRateKey:          config.sampleRate,
      AVNumberOfChannelsKey:    config.numChannels,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
  }

  static func pcmSettings(config: RecordConfig) -> [String: Any] {
    [
      AVFormatIDKey:               kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey:      16,
      AVLinearPCMIsFloatKey:       false,
      AVLinearPCMIsBigEndianKey:   false,
      AVLinearPCMIsNonInterleaved: false,
      AVSampleRateKey:             config.sampleRate,
      AVNumberOfChannelsKey:       config.numChannels,
    ]
  }
}

// MARK: - Narrowing to what the hardware and the encoder allow

private extension FormatNegotiator {
  static func adjustChannelCount(in settings: inout [String: Any], deviceChannels: Int?) {
    guard let requested = settings[AVNumberOfChannelsKey] as? Int else { return }

    let adjusted = max(1, deviceChannels.map { min(requested, $0) } ?? requested)
    if adjusted != requested { settings[AVNumberOfChannelsKey] = adjusted }
  }

  static func adjustSampleRate(in settings: inout [String: Any], converter: AVAudioConverter) {
    guard let rate = settings[AVSampleRateKey] as? NSNumber,
          let available = converter.availableEncodeSampleRates else { return }

    settings[AVSampleRateKey] = nearestValue(to: rate, in: available, key: "sample rates").doubleValue
  }

  static func adjustBitRate(in settings: inout [String: Any], converter: AVAudioConverter) {
    guard let rate = settings[AVEncoderBitRateKey] as? NSNumber,
          let available = converter.availableEncodeBitRates else { return }

    settings[AVEncoderBitRateKey] = nearestValue(to: rate, in: available, key: "bit rates").intValue
  }

  static func nearestValue(to value: NSNumber, in values: [NSNumber], key: String) -> NSNumber {
    guard !values.isEmpty, !(values.count == 1 && values[0] == 0) else { return value }

    var bestIdx = 0
    var bestDist = abs(values[0].floatValue - value.floatValue)
    for i in 1..<values.count {
      let d = abs(values[i].floatValue - value.floatValue)
      if d < bestDist { bestIdx = i; bestDist = d }
    }

    if values[bestIdx] != value {
      print("Available \(key): \(values). Given \(value) adjusted to \(values[bestIdx]).")
    }
    return values[bestIdx]
  }
}
