import AVFoundation

class Pcm16BitsEncoder: AudioEnc {
  func setup(config: RecordConfig, format: AVAudioFormat) throws {}

  func encode(buffer: AVAudioPCMBuffer) -> [Data] {
    guard let channelData = buffer.int16ChannelData else { return [] }

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
    return [bytes]
  }

  func dispose() {}
}
