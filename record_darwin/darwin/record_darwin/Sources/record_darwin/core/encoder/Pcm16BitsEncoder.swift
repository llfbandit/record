import AVFoundation

class Pcm16BitsEncoder: AudioEnc {
  // Apple platforms are little-endian, so the bytes are PCM16 LE as is.
  func encode(buffer: AVAudioPCMBuffer) -> [Data] {
    var samples = [Int16]()
    guard buffer.appendInterleavedInt16(to: &samples) else { return [] }

    return [samples.withUnsafeBytes { Data($0) }]
  }

  func dispose() {}
}
