import AVFoundation

protocol AudioEnc {
  func encode(buffer: AVAudioPCMBuffer) -> [Data]
  func dispose()
}

extension AVAudioPCMBuffer {
  // Adds the Int16 samples, channels interleaved. False if the buffer is not Int16.
  func appendInterleavedInt16(to samples: inout [Int16]) -> Bool {
    guard let channelData = int16ChannelData else { return false }

    let frameCount = Int(frameLength)
    let channels = Int(format.channelCount)
    samples.reserveCapacity(samples.count + frameCount * channels)

    if channels == 1 {
      samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frameCount))
      return true
    }

    for frame in 0..<frameCount {
      for ch in 0..<channels {
        samples.append(channelData[ch][frame])
      }
    }
    return true
  }
}
