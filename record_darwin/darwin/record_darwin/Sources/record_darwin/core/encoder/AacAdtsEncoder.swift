import AVFoundation

// Runs under the capture lock.
class AacAdtsEncoder: AudioEnc {
  private var audioConverter: AudioConverterRef?
  private var pcmBuffer: [Int16] = []
  // Only what the ADTS header needs, so encode() copies nothing.
  private let sampleRate: Int

  private static let framesPerPacket = 1024
  // AAC-LC allows 6144 bits per channel. 8192 bytes is enough.
  private static let outputBufferSize = 8192
  // Reused for each packet.
  private let outputBuffer: UnsafeMutablePointer<UInt8>

  // The format must be Int16, interleaved.
  init(config: RecordConfig, format: AVAudioFormat) throws {
    var srcFormat = format.streamDescription.pointee

    var dstFormat = AudioStreamBasicDescription(
      mSampleRate: Double(config.sampleRate),
      mFormatID: kAudioFormatMPEG4AAC,
      mFormatFlags: 0,
      mBytesPerPacket: 0,
      mFramesPerPacket: UInt32(Self.framesPerPacket),
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
    
    // A refused bit rate makes each packet fail later, silently. So fail now.
    var bitRate = UInt32(config.bitRate)
    let bitRateStatus = AudioConverterSetProperty(
      converter,
      kAudioConverterEncodeBitRate,
      UInt32(MemoryLayout<UInt32>.size),
      &bitRate
    )
    guard bitRateStatus == noErr else {
      AudioConverterDispose(converter)
      throw RecorderError.error(
        message: "Failed to create AAC encoder",
        details: "Bit rate \(config.bitRate) refused with status: \(bitRateStatus)"
      )
    }
    
    sampleRate = config.sampleRate
    audioConverter = converter
    outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.outputBufferSize)
  }

  deinit {
    outputBuffer.deallocate()
  }
  
  func encode(buffer: AVAudioPCMBuffer) -> [Data] {
    let channels = Int(buffer.format.channelCount)

    guard let converter = audioConverter, let samples = buffer.int16ChannelData?[0] else { return [] }
    pcmBuffer.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength) * channels))

    let samplesPerPacket = Self.framesPerPacket * channels
    var aacDataList: [Data] = []
    var readIndex = 0

    while readIndex + samplesPerPacket <= pcmBuffer.count {
      let packet = pcmBuffer.withUnsafeBufferPointer { samples in
        encode(
          UnsafeBufferPointer(rebasing: samples[readIndex..<readIndex + samplesPerPacket]),
          converter: converter,
          channels: channels
        )
      }
      if let packet { aacDataList.append(packet) }
      readIndex += samplesPerPacket
    }

    // Keeps the rest for the next call, in place.
    pcmBuffer.removeFirst(readIndex)

    return aacDataList
  }

  private func encode(_ pcmSamples: UnsafeBufferPointer<Int16>, converter: AudioConverterRef, channels: Int) -> Data? {
    guard let baseAddress = pcmSamples.baseAddress else { return nil }

    let inputBuffer = AudioBuffer(
      mNumberChannels: UInt32(channels),
      mDataByteSize: UInt32(pcmSamples.count * 2),
      mData: UnsafeMutableRawPointer(mutating: baseAddress)
    )

    var inputBufferList = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: inputBuffer
    )

    let outputAudioBuffer = AudioBuffer(
      mNumberChannels: UInt32(channels),
      mDataByteSize: UInt32(Self.outputBufferSize),
      mData: UnsafeMutableRawPointer(outputBuffer)
    )

    var outputBufferList = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: outputAudioBuffer
    )

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

    let adtsHeader = createADTSHeader(frameLength: frameLength, channels: channels)

    var data = Data(adtsHeader)
    data.append(UnsafeBufferPointer(start: outputBuffer, count: frameLength))

    return data
  }

  private func createADTSHeader(frameLength: Int, channels: Int) -> [UInt8] {
    let packetLength = frameLength + 7 // The header is 7 bytes.
    
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
    adts[1] = 0xF1
    adts[2] = UInt8((aacProfile - 1) << 6) | freqIdx << 2 | UInt8(channels >> 2)
    adts[3] = UInt8((channels & 3) << 6 | (packetLength >> 11) & 0x3)
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
    pcmBuffer.removeAll(keepingCapacity: true)
  }
}
