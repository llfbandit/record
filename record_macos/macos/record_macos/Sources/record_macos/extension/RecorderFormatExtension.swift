import AVFoundation

extension AudioRecordingDelegate {
  func getFileTypeFromSettings(_ settings: [String : Any]) -> AVFileType {
    let formatId = settings[AVFormatIDKey] as! UInt32
    
    switch formatId {
    case kAudioFormatAMR, kAudioFormatAMR_WB:
      return AVFileType.mobile3GPP
    case kAudioFormatLinearPCM:
      return AVFileType.wav
    default:
      return AVFileType.m4a
    }
  }
  
  func getInputSettings(config: RecordConfig) -> [String : Any] {
    let format = AVAudioFormat(
      commonFormat: AVAudioCommonFormat.pcmFormatInt16,
      sampleRate: (config.sampleRate < 48000) ? Double(config.sampleRate) : 48000.0,
      channels: UInt32((config.numChannels > 2) ? 2 : config.numChannels),
      interleaved: false
    )

    return format!.settings
  }

  // https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers
  func getOutputSettings(config: RecordConfig) throws -> [String : Any] {
    var settings: [String : Any]
    var keepSampleRate = false

    switch config.encoder {
    case AudioEncoder.aacLc.rawValue:
      settings = [
        AVFormatIDKey : kAudioFormatMPEG4AAC,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.sampleRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case AudioEncoder.aacEld.rawValue:
      settings = [
        AVFormatIDKey : kAudioFormatMPEG4AAC_ELD_V2,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.sampleRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case AudioEncoder.aacHe.rawValue:
      settings = [
        AVFormatIDKey : kAudioFormatMPEG4AAC_HE_V2,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.sampleRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case AudioEncoder.amrNb.rawValue:
      settings = [
        AVFormatIDKey : kAudioFormatAMR,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: 8000,
        AVNumberOfChannelsKey: config.numChannels,
        AVLinearPCMBitDepthKey: 8,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: true,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case AudioEncoder.amrWb.rawValue:
      settings = [
        AVFormatIDKey : kAudioFormatAMR_WB,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case AudioEncoder.opus.rawValue:
      settings = [
        AVFormatIDKey : kAudioFormatOpus,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.sampleRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case AudioEncoder.flac.rawValue:
      settings = [
        AVFormatIDKey : kAudioFormatFLAC,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.sampleRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case AudioEncoder.pcm16bits.rawValue:
      settings = [
        AVFormatIDKey : kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
        AVSampleRateKey: config.sampleRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
      keepSampleRate = true
    case AudioEncoder.wav.rawValue:
      settings = [
        AVFormatIDKey : kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
        AVSampleRateKey: config.sampleRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
      keepSampleRate = true
    default:
      settings = [
        AVFormatIDKey : kAudioFormatMPEG4AAC,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.sampleRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    }
    
    // Check available settings & adjust them if needed
    guard let inFormat = AVAudioFormat(settings: getInputSettings(config: config)) else {
      throw RecorderError.error(message: "Failed to start recording", details: "Input format initialization failure.")
    }
    guard let outFormat = AVAudioFormat(settings: settings) else {
      throw RecorderError.error(message: "Failed to start recording", details: "Output format initialization failure.")
    }
    guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
      throw RecorderError.error(message: "Failed to start recording", details: "Format conversion isn’t possible. Format or configuration is not supported.")
    }

    if let sampleRate = settings[AVSampleRateKey] as? NSNumber,
       let sampleRates = converter.availableEncodeSampleRates {
      settings[AVSampleRateKey] = nearestValue(values: sampleRates, value: sampleRate, key: "sample rates").floatValue
    } else if !keepSampleRate {
      settings.removeValue(forKey: AVSampleRateKey)
    }
    
    if let bitRate = settings[AVEncoderBitRateKey] as? NSNumber,
       let bitRates = converter.availableEncodeBitRates {
      settings[AVEncoderBitRateKey] = nearestValue(values: bitRates, value: bitRate, key: "bit rates").intValue
    } else {
      settings.removeValue(forKey: AVEncoderBitRateKey)
    }
    
    return settings
  }
  
  private func nearestValue(values: [NSNumber], value: NSNumber, key: String) -> NSNumber {
    // Sometimes converter does not give any good listing
    if values.count == 0 || (values.count == 1 && values[0] == 0) {
      return value
    }
    
    var distance = abs(values[0].floatValue - value.floatValue)
    var idx = 0
    
    for c in 1..<values.count {
      let cdistance = abs(values[c].floatValue - value.floatValue)
      if (cdistance < distance) {
        idx = c
        distance = cdistance
      }
    }
    
    if (values[idx] != value) {
      print("Available \(key): \(values).")
      print("Given \(value) has been adjusted to \(values[idx]).")
    }
    
    return values[idx]
  }
}
