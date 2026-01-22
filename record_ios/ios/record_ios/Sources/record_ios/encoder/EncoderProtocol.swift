import AVFoundation

protocol AudioEnc {
  func setup(config: RecordConfig, format: AVAudioFormat) throws
  func encode(buffer: AVAudioPCMBuffer) -> [Data]
  func dispose()
}
