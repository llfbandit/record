import AVFoundation

class AacAdtsEncoder: AudioEnc {
  private var audioConverter: AudioConverterRef?
  private var outputFormat: AVAudioFormat?
  private var pcmBuffer: [Int16] = []
  private var pcmBufferReadIndex = 0
  private let aacFramesPerPacket = 1024
  private let bufferLock = NSLock()
  private var config: RecordConfig?
  
  func setup(config: RecordConfig, format: AVAudioFormat) throws {
    var srcFormat = AudioStreamBasicDescription(
      mSampleRate: format.sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: UInt32(format.channelCount * 2),
      mFramesPerPacket: 1,
      mBytesPerFrame: UInt32(format.channelCount * 2),
      mChannelsPerFrame: UInt32(format.channelCount),
      mBitsPerChannel: 16,
      mReserved: 0
    )
    
    var dstFormat = AudioStreamBasicDescription(
      mSampleRate: Double(config.sampleRate),
      mFormatID: kAudioFormatMPEG4AAC,
      mFormatFlags: 0,
      mBytesPerPacket: 0,
      mFramesPerPacket: 1024,
      mBytesPerFrame: 0,
      mChannelsPerFrame: UInt32(config.numChannels),
      mBitsPerChannel: 0,
      mReserved: 0
    )
    
    var converter: AudioConverterRef?
    let status = AudioConverterNew(&srcFormat, &dstFormat, &converter)
    
    guard status == noErr, let converter = converter else {
      throw RecorderError.error(
        message: "Failed to create AAC encoder",
        details: "AudioConverter creation failed with status: \(status)"
      )
    }
    
    // Set bitrate
    var bitRate = UInt32(config.bitRate)
    AudioConverterSetProperty(
      converter,
      kAudioConverterEncodeBitRate,
      UInt32(MemoryLayout<UInt32>.size),
      &bitRate
    )
    
    self.config = config
    audioConverter = converter
  }
  
  func encode(buffer: AVAudioPCMBuffer) -> [Data] {
    guard let converter = audioConverter, let channelData = buffer.int16ChannelData else {
      return []
    }
    
    let frameCount = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)

    // Buffer PCM samples
    bufferLock.lock()
    pcmBuffer.reserveCapacity(pcmBuffer.count + frameCount * channels)
    
    // interleave channels
    for frame in 0..<frameCount {
      for ch in 0..<channels {
        let sample = channelData[ch][frame]
        pcmBuffer.append(sample)
      }
    }

    // Encode to AAC
    let samplesPerFrame = aacFramesPerPacket * channels
    var aacDataList: [Data] = []
    
    while pcmBufferReadIndex + samplesPerFrame <= pcmBuffer.count {
      let endIndex = pcmBufferReadIndex + samplesPerFrame
      let framesToEncode = Array(pcmBuffer[pcmBufferReadIndex..<endIndex])
      pcmBufferReadIndex += samplesPerFrame
      
      if let aacData = encode(
        pcmSamples: framesToEncode,
        converter: converter,
        sampleRate: config!.sampleRate,
        channels: channels) {

        aacDataList.append(aacData)
      }
    }
    
    // Compact buffer when read index gets large
    if pcmBufferReadIndex > 10000 {
      pcmBuffer.removeFirst(pcmBufferReadIndex)
      pcmBufferReadIndex = 0
    }
    
    bufferLock.unlock()
    
    return aacDataList
  }
  
  private func encode(pcmSamples: [Int16], converter: AudioConverterRef, sampleRate: Int, channels: Int) -> Data? {
    guard pcmSamples.count == aacFramesPerPacket * channels else {
      return nil
    }
    
    return pcmSamples.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) -> Data? in
      guard let baseAddress = rawBufferPointer.baseAddress else { return nil }
      
      let inputBuffer = AudioBuffer(
        mNumberChannels: UInt32(channels),
        mDataByteSize: UInt32(pcmSamples.count * 2),
        mData: UnsafeMutableRawPointer(mutating: baseAddress)
      )
      
      var inputBufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: inputBuffer
      )
      
      // Prepare output buffer
      let outputBufferSize = 2048
      let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputBufferSize)
      defer { outputBuffer.deallocate() }
      
      let outputAudioBuffer = AudioBuffer(
        mNumberChannels: UInt32(channels),
        mDataByteSize: UInt32(outputBufferSize),
        mData: UnsafeMutableRawPointer(outputBuffer)
      )
      
      var outputBufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: outputAudioBuffer
      )
      
      // Convert
      var ioOutputDataPacketSize: UInt32 = 1
      let status = AudioConverterFillComplexBuffer(
        converter,
        { (_, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData) -> OSStatus in
          let inputBufferList = inUserData!.assumingMemoryBound(to: AudioBufferList.self)
          ioData.pointee = inputBufferList.pointee
          ioNumberDataPackets.pointee = 1
          return noErr
        },
        &inputBufferList,
        &ioOutputDataPacketSize,
        &outputBufferList,
        nil
      )
      
      guard status == noErr, ioOutputDataPacketSize > 0 else {
        return nil
      }
      
      let frameLength = Int(outputBufferList.mBuffers.mDataByteSize)
      
      // Add ADTS header
      let adtsHeader = createADTSHeader(
        frameLength: frameLength,
        sampleRate: sampleRate,
        channels: channels
      )

      // Combine ADTS header + frame
      var data = Data(adtsHeader)
      data.append(UnsafeBufferPointer(start: outputBuffer, count: frameLength))
      
      return data
    }
  }
  
  private func createADTSHeader(frameLength: Int, sampleRate: Int, channels: Int) -> [UInt8] {
    let packetLength = frameLength + 7 // 7 bytes for ADTS header
    
    // Sample rate index
    let freqIdx: UInt8 = {
      switch sampleRate {
      case 96000: return 0
      case 88200: return 1
      case 64000: return 2
      case 48000: return 3
      case 44100: return 4
      case 32000: return 5
      case 24000: return 6
      case 22050: return 7
      case 16000: return 8
      case 12000: return 9
      case 11025: return 10
      case 8000: return 11
      default: return 4
      }
    }()

    let aacProfile = 2 // AAC LC

    var adts: [UInt8] = [0, 0, 0, 0, 0, 0, 0]
    adts[0] = 0xFF
    adts[1] = 0xF9
    adts[2] = UInt8((aacProfile - 1) << 6) | freqIdx << 2 | UInt8(channels >> 2)
    adts[3] = UInt8((channels & 3) << 6 | packetLength >> 11)
    adts[4] = UInt8((packetLength & 0x7FF) >> 3)
    adts[5] = UInt8((packetLength & 7) << 5 | 0x1F)
    adts[6] = 0xFC

    return adts
  }
  
  func dispose() {
    if let converter = audioConverter {
      AudioConverterDispose(converter)
      audioConverter = nil
    }
    
    bufferLock.lock()
    pcmBuffer.removeAll(keepingCapacity: true)
    pcmBufferReadIndex = 0
    bufferLock.unlock()
  }
}
