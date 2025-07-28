import AVFoundation
import Foundation
import FlutterMacOS

class RecorderStreamDelegate: NSObject, AudioRecordingStreamDelegate {
  private var audioEngine: AVAudioEngine?
  private var amplitude: Float = -160.0
  private let bus = 0
  private var onPause: () -> ()
  private var onStop: () -> ()
  
  init(onPause: @escaping () -> (), onStop: @escaping () -> ()) {
    self.onPause = onPause
    self.onStop = onStop
  }

  func start(config: RecordConfig, recordEventHandler: RecordStreamHandler) throws {
    let audioEngine = AVAudioEngine()

    // set input device to the node
    if let deviceId = config.device?.id,
       let inputDeviceId = getAudioDeviceIDFromUID(uid: deviceId) {
      do {
        try audioEngine.inputNode.auAudioUnit.setDeviceID(inputDeviceId)
      } catch {
        throw RecorderError.error(
          message: "Failed to start recording",
          details: "Setting input device: \(deviceId) \(error)"
        )
      }
    }

    // Set up voice processing on macOS before getting the format if echo cancel or auto gain is to be applied
    if config.echoCancel || config.autoGain {
      try setVoiceProcessing(echoCancel: config.echoCancel, autoGain: config.autoGain, audioEngine: audioEngine)
    }
    
    let srcFormat = audioEngine.inputNode.inputFormat(forBus: 0)
    
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
  }
  
  func stop(completionHandler: @escaping (String?) -> ()) {
    audioEngine?.inputNode.removeTap(onBus: bus)
    audioEngine?.stop()
    audioEngine = nil
    
    completionHandler(nil)
    onStop()
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
    let bufferToConvert: AVAudioPCMBuffer
    let converterToUse: AVAudioConverter

    if buffer.format.channelCount > 1 {
      // Create a mono version of the buffer and a new converter for it
      guard let monoFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: buffer.format.sampleRate,
        channels: 1,
        interleaved: false
      ) else { return }

      guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength) else { return }
      monoBuffer.frameLength = buffer.frameLength

      // Copy the first channel
      if let src = buffer.floatChannelData, let dst = monoBuffer.floatChannelData {
          memcpy(dst[0], src[0], Int(buffer.frameLength) * MemoryLayout<Float>.size)
      }

      guard let monoConverter = AVAudioConverter(from: monoFormat, to: dstFormat) else { return }
      monoConverter.sampleRateConverterQuality = AVAudioQuality.high.rawValue

      bufferToConvert = monoBuffer
      converterToUse = monoConverter
    } else {
      bufferToConvert = buffer
      converterToUse = converter
    }

    let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return bufferToConvert
    }

    // Determine frame capacity
    let capacity = AVAudioFrameCount(Double(bufferToConvert.frameLength) * dstFormat.sampleRate / bufferToConvert.format.sampleRate)

    // Destination buffer
    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: capacity) else {
      print("Unable to create output buffer")
      stop { path in }
      return
    }

    // Convert input buffer (resample, num channels)
    var error: NSError? = nil
    converterToUse.convert(to: convertedBuffer, error: &error, withInputFrom: inputCallback)
    if error != nil {
      return
    }

    if let channelData = convertedBuffer.int16ChannelData {
      // Fill samples
      let channelDataPointer = channelData.pointee
      let samples = stride(from: 0,
                           to: Int(convertedBuffer.frameLength),
                           by: convertedBuffer.stride).map{ channelDataPointer[$0] }

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

  // Set up AGC & echo cancel
  private func setVoiceProcessing(echoCancel: Bool, autoGain: Bool, audioEngine: AVAudioEngine) throws {
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
