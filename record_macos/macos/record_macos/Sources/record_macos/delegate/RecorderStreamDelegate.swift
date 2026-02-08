import AVFoundation
import Foundation
import FlutterMacOS

class RecorderStreamDelegate: NSObject, AudioRecordingStreamDelegate {
  var config: RecordConfig?

  private var audioEngine: AVAudioEngine?
  private var amplitude: Float = -160.0
  private let bus = 0
  private var onPause: () -> ()
  private var onStop: () -> ()

  private var audioEncoder: AudioEnc?
  private var outputFormat: AVAudioFormat?
  private var targetSampleRate: Double = 44100.0
  private var targetChannels: Int = 1
  
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

    if config.echoCancel || config.autoGain {
      try setVoiceProcessing(echoCancel: config.echoCancel, autoGain: config.autoGain, audioEngine: audioEngine)
    }
    
    targetSampleRate = Double(config.sampleRate)
    targetChannels = config.numChannels

    outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: targetSampleRate,
      channels: AVAudioChannelCount(targetChannels),
      interleaved: true
    )
    
    guard outputFormat != nil else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format is not supported: \(config.sampleRate)Hz - \(config.numChannels) channels."
      )
    }

    // Tap with the native source format — this is the only format guaranteed to work
    let srcFormat = audioEngine.inputNode.inputFormat(forBus: 0)

    audioEngine.inputNode.installTap(
      onBus: bus,
      bufferSize: AVAudioFrameCount(config.streamBufferSize ?? 1024),
      format: srcFormat) { (buffer, _) -> Void in

      self.stream(
        buffer: buffer,
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
  
  private func updateAmplitudeFloat(buffer: AVAudioPCMBuffer) {
    guard let floatData = buffer.floatChannelData else {
      return
    }
    
    let frameCount = Int(buffer.frameLength)
    var maxSample: Float = 0.0
    
    for i in 0..<frameCount {
      let curSample = abs(floatData[0][i])
      if curSample > maxSample {
        maxSample = curSample
      }
    }
    
    if maxSample > 0 {
      amplitude = 20 * (log(maxSample) / log(10))
    } else {
      amplitude = -160.0
    }
  }

  private func stream(
    buffer: AVAudioPCMBuffer,
    recordEventHandler: RecordStreamHandler
  ) -> Void {

    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    print("[STREAM] frames=\(frameCount), channels=\(channelCount), rate=\(buffer.format.sampleRate)")

    guard frameCount > 0, channelCount > 0 else {
      print("[STREAM] Empty buffer, skipping")
      return
    }

    updateAmplitudeFloat(buffer: buffer)

    // Manual downmix + resample + convert
    let data = manualConvert(buffer: buffer)
    print("[STREAM] converted \(data.count) bytes")

    if config?.encoder == AudioEncoder.pcm16bits.rawValue {
      sendBytes(dataList: [data], recordEventHandler: recordEventHandler)
    } else if config?.encoder == AudioEncoder.aacLc.rawValue {
      sendBytes(dataList: [data], recordEventHandler: recordEventHandler)
    }
  }

  // Downmix to mono (ch0), resample via linear interpolation, convert float to int16 LE bytes
  private func manualConvert(buffer: AVAudioPCMBuffer) -> Data {
    guard let floatData = buffer.floatChannelData else {
      print("[CONVERT] No float channel data!")
      return Data()
    }

    let srcFrameCount = Int(buffer.frameLength)
    let srcRate = buffer.format.sampleRate
    let dstRate = targetSampleRate

    // Find the channel with the most audio energy (not always ch0)
    let channels = Int(buffer.format.channelCount)
    var bestChannel = 0
    var bestMax: Float = 0.0
    for ch in 0..<channels {
      var chMax: Float = 0.0
      for i in 0..<srcFrameCount {
        let v = abs(floatData[ch][i])
        if v > chMax { chMax = v }
      }
      if chMax > bestMax {
        bestMax = chMax
        bestChannel = ch
      }
    }
    let srcChannel = floatData[bestChannel]

    // Calculate output frame count based on sample rate ratio
    let dstFrameCount = Int(Double(srcFrameCount) * dstRate / srcRate)

    var bytes = Data(capacity: dstFrameCount * targetChannels * 2)

    for i in 0..<dstFrameCount {
      // Map output sample index to fractional input index
      let srcIndex = Double(i) * srcRate / dstRate
      let idx0 = Int(srcIndex)
      let frac = Float(srcIndex - Double(idx0))

      let s0 = srcChannel[min(idx0, srcFrameCount - 1)]
      let s1 = srcChannel[min(idx0 + 1, srcFrameCount - 1)]
      let sample = s0 + frac * (s1 - s0)

      let clamped = max(-1.0, min(1.0, sample))
      let int16Val = Int16(clamped * 32767.0)

      // Little-endian
      bytes.append(UInt8(int16Val & 0x00FF))
      bytes.append(UInt8((int16Val >> 8) & 0x00FF))
    }

    return bytes
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

  private func convertFloatToInt16Bytes(buffer: AVAudioPCMBuffer) -> Data {
    guard let floatData = buffer.floatChannelData else {
      return Data()
    }

    let frameCount = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)

    var bytes = Data(capacity: frameCount * channels * 2)
    for i in 0..<frameCount {
      for ch in 0..<channels {
        let sample = floatData[ch][i]
        let clamped = max(-1.0, min(1.0, sample))
        let int16Val = Int16(clamped * 32767.0)
        // Little-endian
        bytes.append(UInt8(int16Val & 0x00FF))
        bytes.append(UInt8((int16Val >> 8) & 0x00FF))
      }
    }

    return bytes
  }

  private func convertFloatToInt16(
    buffer: AVAudioPCMBuffer,
    dstFormat: AVAudioFormat) -> AVAudioPCMBuffer? {

    guard let floatData = buffer.floatChannelData else {
      print("No float channel data in buffer")
      return nil
    }

    // Use non-interleaved format for AVAudioPCMBuffer compatibility
    guard let niFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: dstFormat.sampleRate,
      channels: dstFormat.channelCount,
      interleaved: false
    ) else {
      print("Unable to create non-interleaved int16 format")
      return nil
    }

    let frameCount = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)

    guard let int16Buffer = AVAudioPCMBuffer(pcmFormat: niFormat, frameCapacity: buffer.frameLength) else {
      print("Unable to create int16 output buffer")
      return nil
    }
    int16Buffer.frameLength = buffer.frameLength

    guard let int16Data = int16Buffer.int16ChannelData else {
      print("No int16 channel data in output buffer")
      return nil
    }

    for ch in 0..<channels {
      for i in 0..<frameCount {
        let sample = floatData[ch][i]
        let clamped = max(-1.0, min(1.0, sample))
        int16Data[ch][i] = Int16(clamped * 32767.0)
      }
    }

    return int16Buffer
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
