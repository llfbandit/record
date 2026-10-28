import AVFoundation

class RawPcmEncoder: AudioEnc {
  // Apple platforms are little-endian, so the bytes are PCM LE as is.
  func encode(buffer: AVAudioPCMBuffer) -> [Data] {
    guard let samples = buffer.audioBufferList.pointee.mBuffers.mData else { return [] }

    let size = Int(buffer.frameLength * buffer.format.streamDescription.pointee.mBytesPerFrame)
    return [Data(bytes: samples, count: size)]
  }

  func dispose() {}
}
