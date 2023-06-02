import Foundation
import AVFoundation

enum RecorderError: Error {
  case start(message: String, details: String?)
}

enum RecordState: Int {
  case pause = 0
  case record = 1
  case stop = 2
}

class RecordConfig {
  let encoder: String
  let bitRate: Int
  let samplingRate: Int
  let numChannels: Int
  let device: [String: Any]?
  let autoGain: Bool
  let echoCancel: Bool
  let noiseCancel: Bool
  
  init(encoder: String,
       bitRate: Int,
       samplingRate: Int,
       numChannels: Int,
       device: [String : Any]? = nil,
       autoGain: Bool = false,
       echoCancel: Bool = false,
       noiseCancel: Bool = false
  ) {
    self.encoder = encoder
    self.bitRate = bitRate
    self.samplingRate = samplingRate
    self.numChannels = numChannels
    self.device = device
    self.autoGain = autoGain
    self.echoCancel = echoCancel
    self.noiseCancel = noiseCancel
  }
}

protocol RecorderProtocol {
  func dispose()
  
  func start(config: RecordConfig, path: String) throws
  
  func startStream(config: RecordConfig) throws
  
  func stop() -> String?
  
  func pause()
  
  func resume() throws
  
  func isPaused() -> Bool
  
  func isRecording() -> Bool
  
  func getAmplitude() -> [String : Float]
}

extension RecorderProtocol {
  func writeToStream(_ sampleBuffer: CMSampleBuffer, config: RecordConfig?, recordEventHandler: RecordStreamHandler?) {
    guard let eventSink = recordEventHandler?.eventSink, let config = config else {
      return
    }
    
    let audioBuffer = AudioBuffer(mNumberChannels: UInt32(config.numChannels), mDataByteSize: 0, mData: nil)
    var audioBufferList = AudioBufferList(mNumberBuffers: UInt32(config.numChannels), mBuffers: audioBuffer)
    var blockBuffer: CMBlockBuffer?
    
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: &audioBufferList,
      bufferListSize: MemoryLayout<AudioBufferList>.size(ofValue: audioBufferList),
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
      blockBufferOut: &blockBuffer)
    
    guard let bufferData = audioBufferList.mBuffers.mData else {
      return
    }
    
    let data = Data(bytesNoCopy: bufferData, count: Int(audioBufferList.mBuffers.mDataByteSize), deallocator: .none)
    
    if !data.isEmpty {
      eventSink(FlutterStandardTypedData(bytes: data))
    }
  }
  
  func listInputDevices() -> [AVCaptureDevice] {
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInMicrophone],
      mediaType: .audio, position: .unspecified
    )
    
    return discoverySession.devices
  }
  
  func isEncoderSupported(_ encoder: String) -> Bool {
    switch(encoder) {
    case "aacLc", "aacEld", "aacHe", "amrNb", "amrWb", "opus", "flac", "pcm8bit", "pcm16bit":
      return true
    default:
      return false
    }
  }
  
  func deleteFile(path: String) throws {
    do {
      let fileManager = FileManager.default
      
      if fileManager.fileExists(atPath: path) {
        try fileManager.removeItem(atPath: path)
      }
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: error.localizedDescription)
    }
  }
  
  func getInputDevice(device: [String: Any]?) -> AVCaptureDevice? {
    guard let device = device else {
      // Fallback to default device
      let defaultDevice = AVCaptureDevice.default(for: .audio)
      guard let defaultDevice = defaultDevice else {
        return nil
      }
      
      return defaultDevice
    }
    
    // find the given device
    let devs = listInputDevices()
    let captureDev = devs.first { dev in
      dev.uniqueID == device["id"] as! String
    }
    guard let captureDev = captureDev else {
      return nil
    }
    
    return captureDev
  }
  
  func getRecordingInputDevice(config: RecordConfig) throws -> AVCaptureDeviceInput {
    guard let dev = getInputDevice(device: config.device) else {
      throw RecorderError.start(message: "Failed to start recording", details: "Input device not found.")
    }

    do {
      return try AVCaptureDeviceInput(device: dev)
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: error.localizedDescription)
    }
  }

  func getInputSettings(config: RecordConfig) -> [String : Any] {
    let format = AVAudioFormat(
      commonFormat: AVAudioCommonFormat.pcmFormatInt16,
      sampleRate: (config.samplingRate < 48000) ? Double(config.samplingRate) : 48000.0,
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
    case "aacLc":
      settings = [
        AVFormatIDKey : kAudioFormatMPEG4AAC,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.samplingRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case "aacEld":
      settings = [
        AVFormatIDKey : kAudioFormatMPEG4AAC_ELD_V2,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.samplingRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case "aacHe":
      settings = [
        AVFormatIDKey : kAudioFormatMPEG4AAC_HE_V2,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.samplingRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case "amrNb":
      settings = [
        AVFormatIDKey : kAudioFormatAMR,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: 8000,
        AVNumberOfChannelsKey: config.numChannels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: true,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case "amrWb":
      settings = [
        AVFormatIDKey : kAudioFormatAMR_WB,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: config.numChannels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: true,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case "opus":
      settings = [
        AVFormatIDKey : kAudioFormatOpus,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.samplingRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case "flac":
      settings = [
        AVFormatIDKey : kAudioFormatFLAC,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.samplingRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    case "pcm8bit":
      settings = [
        AVFormatIDKey : kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 8,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVSampleRateKey: config.samplingRate,
        AVNumberOfChannelsKey: config.numChannels,
      ]
      keepSampleRate = true
    case "pcm16bit":
      settings = [
        AVFormatIDKey : kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVSampleRateKey: config.samplingRate,
        AVNumberOfChannelsKey: config.numChannels,
      ]
      keepSampleRate = true
    default:
      settings = [
        AVFormatIDKey : kAudioFormatMPEG4AAC,
        AVEncoderBitRateKey: config.bitRate,
        AVSampleRateKey: config.samplingRate,
        AVNumberOfChannelsKey: config.numChannels,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
    }
    
    // Check available settings & adjust them if needed
    guard let inFormat = AVAudioFormat(settings: getInputSettings(config: config)) else {
      throw RecorderError.start(message: "Failed to start recording", details: "Input format initialization failure.")
    }
    guard let outFormat = AVAudioFormat(settings: settings) else {
      throw RecorderError.start(message: "Failed to start recording", details: "Output format initialization failure.")
    }
    guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
      return settings
      //throw RecorderError.start(message: "Failed to start recording", details: "Format conversion isn’t possible. Format or configuration is not supported.")
    }
    
    if let sampleRate = settings[AVSampleRateKey] as? NSNumber,
       let sampleRates = converter.availableEncodeSampleRates {
      settings[AVSampleRateKey] = nearestValue(values: sampleRates, value: sampleRate, key: "sample rates").doubleValue
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
    
    var distance = abs(values[0].decimalValue - value.decimalValue)
    var idx = 0
    
    for c in 1..<values.count {
      let cdistance = abs(values[c].decimalValue - value.decimalValue)
      if (cdistance < distance) {
        idx = c
        distance = cdistance
      }
    }
    
    if (values[idx] != value) {
      print("Available \(key): \(values).")
      print("Adjusted to \(values[idx]).")
    }
    
    return values[idx]
  }
}
