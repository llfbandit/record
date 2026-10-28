import AVFoundation

// The buffers are interleaved.
protocol AudioEnc {
  func encode(buffer: AVAudioPCMBuffer) -> [Data]
  func dispose()
}
