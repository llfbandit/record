import AVFoundation

// Turns a config into output settings and tells what was accepted.
// https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers
enum FormatPolicy {
  // The input format comes from the capture graph. It is what the hardware really gives.
  static func negotiate(
    for config: RecordConfig,
    input: AVAudioFormat
  ) throws -> (settings: [String: Any], effective: RecordConfig) {
    // Zero means the graph has no input yet. We treat it as unknown.
    let inputChannels = input.channelCount > 0 ? Int(input.channelCount) : nil
    let inputSampleRate = input.sampleRate > 0 ? input.sampleRate : nil

    // Never more channels than the input has.
    let channels = max(1, min(config.numChannels, inputChannels ?? config.numChannels))

    var settings = try initialSettings(for: config)
    settings[AVNumberOfChannelsKey] = channels

    let inFormat = try AVAudioFormat.int16(sampleRate: inputSampleRate ?? Double(config.sampleRate), channels: channels)
    guard let outFormat = AVAudioFormat(settings: settings) else {
      throw RecorderError.startFailed("Output format initialization failure.")
    }
    let converter = try AVAudioConverter.make(from: inFormat, to: outFormat)

    adjustSampleRate(in: &settings, converter: converter)
    adjustBitRate(in: &settings, converter: bitRateConverter(from: inFormat, settings: settings) ?? converter)

    // If the encoder has no such key, we keep the value that was asked.
    let effective = config.negotiated(
      sampleRate: (settings[AVSampleRateKey] as? Double).map { Int($0) } ?? config.sampleRate,
      bitRate: settings[AVEncoderBitRateKey] as? Int ?? config.bitRate,
      numChannels: channels
    )

    return (settings, effective)
  }

  // The file container for an encoder. Nil means raw samples with no header.
  static func fileType(for encoder: String) -> AudioFileTypeID? {
    switch encoder {
    case AudioEncoder.opus.rawValue:      return kAudioFileCAFType
    case AudioEncoder.flac.rawValue:      return kAudioFileFLACType
    case AudioEncoder.wav.rawValue:       return kAudioFileWAVEType
    case AudioEncoder.pcm16bits.rawValue: return nil
    default:                              return kAudioFileM4AType
    }
  }
}

// MARK: - Per-encoder initial settings

private extension FormatPolicy {
  static func initialSettings(for config: RecordConfig) throws -> [String: Any] {
    switch config.encoder {
    case AudioEncoder.aacLc.rawValue:  return encodedSettings(kAudioFormatMPEG4AAC, config)
    case AudioEncoder.aacEld.rawValue: return encodedSettings(kAudioFormatMPEG4AAC_ELD, config)
    // iOS has no HE v2 encoder.
    case AudioEncoder.aacHe.rawValue:  return encodedSettings(kAudioFormatMPEG4AAC_HE, config)
    case AudioEncoder.opus.rawValue:   return encodedSettings(kAudioFormatOpus, config)
    case AudioEncoder.flac.rawValue:   return encodedSettings(kAudioFormatFLAC, config, hasBitRate: false)
    case AudioEncoder.pcm16bits.rawValue,
         AudioEncoder.wav.rawValue:    return pcmSettings(config: config)
    default:
      throw RecorderError.startFailed("\(config.encoder) not supported.")
    }
  }

  static func encodedSettings(_ formatId: AudioFormatID, _ config: RecordConfig, hasBitRate: Bool = true) -> [String: Any] {
    var settings: [String: Any] = [
      AVFormatIDKey:            formatId,
      AVSampleRateKey:          config.sampleRate,
      AVNumberOfChannelsKey:    config.numChannels,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
    if hasBitRate { settings[AVEncoderBitRateKey] = config.bitRate }
    return settings
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

private extension FormatPolicy {
  static func adjustSampleRate(in settings: inout [String: Any], converter: AVAudioConverter) {
    guard let rate = settings[AVSampleRateKey] as? NSNumber,
          let available = converter.availableEncodeSampleRates else { return }

    settings[AVSampleRateKey] = nearestValue(to: rate, in: available, key: "sample rates").doubleValue
  }

  // Valid bit rates depend on the rate and channels. So we ask a converter built with the final ones.
  static func bitRateConverter(from inFormat: AVAudioFormat, settings: [String: Any]) -> AVAudioConverter? {
    AVAudioFormat(settings: settings).flatMap { try? AVAudioConverter.make(from: inFormat, to: $0) }
  }

  // "available" also lists rates this format refuses, like 320k for mono AAC.
  static func adjustBitRate(in settings: inout [String: Any], converter: AVAudioConverter) {
    guard let rate = settings[AVEncoderBitRateKey] as? NSNumber else { return }

    let applicable = converter.applicableEncodeBitRates ?? []
    guard let rates = applicable.isEmpty ? converter.availableEncodeBitRates : applicable else { return }

    settings[AVEncoderBitRateKey] = nearestValue(to: rate, in: rates, key: "bit rates").intValue
  }

  static func nearestValue(to value: NSNumber, in values: [NSNumber], key: String) -> NSNumber {
    guard !values.isEmpty, !(values.count == 1 && values[0] == 0) else { return value }

    let distance = { (n: NSNumber) in abs(n.floatValue - value.floatValue) }
    guard let best = values.min(by: { distance($0) < distance($1) }) else { return value }

    if best != value {
      print("Available \(key): \(values). Given \(value) adjusted to \(best).")
    }
    return best
  }
}
