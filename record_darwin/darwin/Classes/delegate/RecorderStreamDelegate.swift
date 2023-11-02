import AVFoundation
import Foundation

class RecorderStreamDelegate: NSObject, AudioRecordingStreamDelegate {
  private var audioEngine: AVAudioEngine?
  private var amplitude: Float = -160.0
  private let bus = 0

  func start(config: RecordConfig, recordEventHandler: RecordStreamHandler) throws {
#if os(iOS)
    try initAVAudioSession(config: config)
#endif
    let audioEngine = AVAudioEngine()

    let inputNode = audioEngine.inputNode
    let srcFormat = inputNode.outputFormat(forBus: 0)
    let dstFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(config.sampleRate),
      channels: AVAudioChannelCount(config.numChannels),
      interleaved: true
    )

    guard let dstFormat = dstFormat else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format is not supported: \(config.sampleRate)Hz - \(config.numChannels) channels."
      )
    }
    
    let converter = AVAudioConverter(from: srcFormat, to: dstFormat)
    
    guard let converter = converter else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format conversion is not possible."
      )
    }
    converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
    
    inputNode.installTap(onBus: bus, bufferSize: 2048, format: srcFormat) { (buffer, _) -> Void in
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
  }
  
  func stop(completionHandler: @escaping (String?) -> ()) {
    audioEngine?.inputNode.removeTap(onBus: bus)
    audioEngine?.stop()
    audioEngine = nil
    
    completionHandler(nil)
  }
  
  func pause() {
    audioEngine?.pause()
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
  
  private func updateAmplitude(_ samples: [Int16]) {
    var maxSample:Float = -160.0

    for sample in samples {
      let curSample = abs(Float(sample))
      if (curSample > maxSample) {
        maxSample = curSample
      }
    }
    
    amplitude = 20 * (log(maxSample / 32767.0) / log(10))
  }
  
  func dispose() {
    stop { path in }
  }
  
  // Little endian
  private func convertInt16toUInt8(_ samples: [Int16]) -> [UInt8] {
    var bytes: [UInt8] = []
    
    for sample in samples {
      bytes.append(UInt8(sample & 0x00ff))
      bytes.append(UInt8(sample >> 8 & 0x00ff))
    }
    
    return bytes
  }
  
  private func stream(
    buffer: AVAudioPCMBuffer,
    dstFormat: AVAudioFormat,
    converter: AVAudioConverter,
    recordEventHandler: RecordStreamHandler
  ) -> Void {
    let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }
    
    // Determine frame capacity
    let capacity = (UInt32(dstFormat.sampleRate) * dstFormat.channelCount * buffer.frameLength) / (UInt32(buffer.format.sampleRate) * buffer.format.channelCount)
    
    // Destination buffer
    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: capacity) else {
      print("Unable to create output buffer")
      stop { path in }
      return
    }
    
    // Convert input buffer (resample, num channels)
    var error: NSError? = nil
    converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputCallback)
    if let error = error {
      print(error.localizedDescription)
      return
    }
    
    if let channelData = convertedBuffer.int16ChannelData {
      // Fill samples
      let channelDataPointer = channelData.pointee
      let samples = stride(from: 0,
                           to: Int(convertedBuffer.frameLength),
                           by: buffer.stride).map{ channelDataPointer[$0] }
      //        let arraySize = Int(buffer.frameLength)
      //        let samples = Array(UnsafeBufferPointer(start: channelData.pointee, count: arraySize))

      // Update current amplitude
      updateAmplitude(samples)
      
      // Send bytes
      if let eventSink = recordEventHandler.eventSink {
        let bytes = Data(_: convertInt16toUInt8(samples))
        
        DispatchQueue.main.async {
          eventSink(FlutterStandardTypedData(bytes: bytes))
        }
      }
    }
  }
}
