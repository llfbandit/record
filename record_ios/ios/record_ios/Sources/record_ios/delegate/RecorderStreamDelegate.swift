import AVFoundation
import Foundation
import Flutter

class RecorderStreamDelegate: NSObject, AudioRecordingStreamDelegate {
  var config: RecordConfig?
  
  private var audioEngine: AVAudioEngine?
  private var amplitude: Float = -160.0
  private let bus = 0
  private var onPause: () -> ()
  private var onStop: () -> ()
  private let manageAudioSession: Bool
  
  private var audioEncoder: AudioEnc?
  private var outputFormat: AVAudioFormat?
  
  init(manageAudioSession: Bool, onPause: @escaping () -> (), onStop: @escaping () -> ()) {
    self.manageAudioSession = manageAudioSession
    self.onPause = onPause
    self.onStop = onStop
  }
  
  func start(config: RecordConfig, recordEventHandler: RecordStreamHandler) throws {
    let audioEngine = AVAudioEngine()
    
    try initAVAudioSession(config: config, manageAudioSession: manageAudioSession)
    try setVoiceProcessing(echoCancel: config.echoCancel, autoGain: config.autoGain, audioEngine: audioEngine)
    
    let srcFormat = audioEngine.inputNode.inputFormat(forBus: 0)
    
    outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(config.sampleRate),
      channels: AVAudioChannelCount(config.numChannels),
      interleaved: true
    )
    
    guard let dstFormat = outputFormat else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format is not supported: \(config.sampleRate)Hz - \(config.numChannels) channels."
      )
    }
    
    guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format conversion is not possible."
      )
    }
    converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
    
    
    audioEngine.inputNode.installTap(
      onBus: bus,
      bufferSize: AVAudioFrameCount(config.streamBufferSize ?? 1024),
      format: srcFormat) { (buffer, _) -> Void in
        
        self.stream(
          buffer: buffer,
          dstFormat: dstFormat,
          converter: converter,
          recordEventHandler: recordEventHandler
        )
      }
    
    audioEngine.prepare()
    try audioEngine.start()
    
    self.audioEngine = audioEngine    
    self.config = config
  }
  
  func stop(completionHandler: @escaping (String?) -> ()) {
    if let audioEngine = audioEngine {
      do {
        try setVoiceProcessing(echoCancel: false, autoGain: false, audioEngine: audioEngine)
      } catch {}
    }
    
    audioEngine?.inputNode.removeTap(onBus: bus)
    audioEngine?.stop()
    audioEngine = nil
    
    if let encoder = audioEncoder {
      encoder.dispose()
      audioEncoder = nil
    }
    outputFormat = nil
    
    completionHandler(nil)
    onStop()
    
    config = nil
  }
  
  func pause() {
    audioEngine?.pause()
    onPause()
  }
  
  func resume() throws {
    try audioEngine?.start()
  }
  
  func cancel() throws {
    stop { path in }
  }
  
  func getAmplitude() -> Float {
    return amplitude
  }
  
  func dispose() {
    stop { path in }
  }
  
  // Set up AGC & echo cancel
  private func setVoiceProcessing(echoCancel: Bool, autoGain: Bool, audioEngine: AVAudioEngine) throws {
    if #available(iOS 13.0, *) {
      do {
        try audioEngine.inputNode.setVoiceProcessingEnabled(echoCancel)
        audioEngine.inputNode.isVoiceProcessingAGCEnabled = autoGain
      } catch {
        throw RecorderError.error(
          message: "Failed to setup voice processing",
          details: "Echo cancel error: \(error)"
        )
      }
    }
  }
  
  private func updateAmplitudeInt16(buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.int16ChannelData else {
      return
    }
    
    let frameCount = Int(buffer.frameLength)
    let firstChannelPointer = channelData[0]
    var maxSample: Float = -160.0
    
    for i in 0..<frameCount {
      let curSample = abs(Float(firstChannelPointer[i]))
      if curSample > maxSample {
        maxSample = curSample
      }
    }
    
    amplitude = 20 * (log(maxSample / 32767.0) / log(10))
  }
  
  private func stream(
    buffer: AVAudioPCMBuffer,
    dstFormat: AVAudioFormat,
    converter: AVAudioConverter,
    recordEventHandler: RecordStreamHandler
  ) -> Void {
    
    guard let convertedBuffer = convertBuffer(buffer: buffer, dstFormat: dstFormat, converter: converter) else {
      stop { path in }
      return
    }
    
    updateAmplitudeInt16(buffer: convertedBuffer)

    if config?.encoder == AudioEncoder.aacLc.rawValue {
      guard let dataList = encodeAac(buffer: convertedBuffer) else {
        stop { path in }
        return
      }
      
      sendBytes(dataList: dataList, recordEventHandler: recordEventHandler)
    } else if config?.encoder == AudioEncoder.pcm16bits.rawValue {
      if let data = convertInt16toUInt8(buffer: convertedBuffer) {
        sendBytes(dataList: [data], recordEventHandler: recordEventHandler)
      }
    }
  }
  
  private func sendBytes(dataList: [Data], recordEventHandler: RecordStreamHandler) {
    // Send bytes
    if let eventSink = recordEventHandler.eventSink {
      for data in dataList {
        DispatchQueue.main.async {
          eventSink(FlutterStandardTypedData(bytes: data))
        }
      }
    }
  }
  
  private func convertBuffer(
    buffer: AVAudioPCMBuffer,
    dstFormat: AVAudioFormat,
    converter: AVAudioConverter) -> AVAudioPCMBuffer? {

    let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }
    
    // Determine frame capacity
    let capacity = (UInt32(dstFormat.sampleRate) * dstFormat.channelCount * buffer.frameLength) / (UInt32(buffer.format.sampleRate) * buffer.format.channelCount)
    
    // Destination buffer
    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: capacity) else {
      print("Unable to create output buffer")
      return nil
    }
    
    // Convert input buffer (resample, num channels)
    var error: NSError? = nil
    converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputCallback)
    if error != nil {
      print("Unable to convert input buffer \(error!)")
      return nil
    }
      
    return convertedBuffer
  }
  
  private func encodeAac(buffer: AVAudioPCMBuffer) -> [Data]? {
    // Lazily initialize AAC encoder
    if audioEncoder == nil {
      audioEncoder = AacAdtsEncoder()
      do {
        try audioEncoder!.setup(config: config!, format: outputFormat!)
      } catch {
        print("Failed to setup AAC encoder: \(error)")
        return nil
      }
    }
    
    guard let encoder = audioEncoder else {
      return nil
    }
    
    return encoder.encode(buffer: buffer)
  }
  
  // Little endian
  private func convertInt16toUInt8(buffer: AVAudioPCMBuffer) -> Data? {
    guard let channelData = buffer.int16ChannelData else {
      return nil
    }
    
    let frameCount = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    
    var bytes = Data(capacity: frameCount * channels * 2)
    for frame in 0..<frameCount {
      for ch in 0..<channels {
        let sample = channelData[ch][frame]
        bytes.append(UInt8(sample & 0x00FF))
        bytes.append(UInt8((sample >> 8) & 0x00FF))
      }
    }
    
    return bytes
  }
}
