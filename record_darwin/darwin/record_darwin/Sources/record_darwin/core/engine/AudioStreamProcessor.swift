import AVFoundation

// Turns tap buffers into PCM16 or AAC chunks, for a stream or a raw PCM file.
class AudioStreamProcessor {
  // The encoders a stream can use.
  static let encoders: Set<String> = [AudioEncoder.aacLc.rawValue, AudioEncoder.pcm16bits.rawValue]

  private let m_converter: AVAudioConverter
  private let m_encoder: AudioEnc

  init(config: RecordConfig, srcFormat: AVAudioFormat) throws {
    let outputFormat = try AVAudioFormat.int16(sampleRate: Double(config.sampleRate), channels: config.numChannels)
    m_converter = try AVAudioConverter.make(from: srcFormat, to: outputFormat)

    if config.encoder == AudioEncoder.aacLc.rawValue {
      m_encoder = try AacAdtsEncoder(config: config, format: outputFormat)
    } else if config.encoder == AudioEncoder.pcm16bits.rawValue {
      m_encoder = Pcm16BitsEncoder()
    } else {
      throw RecorderError.startFailed("Encoder '\(config.encoder)' is not supported for stream recording.")
    }
  }

  // Converts and encodes one tap buffer. Returns `[]` while the encoder waits for more data.
  func process(buffer: AVAudioPCMBuffer) throws -> [Data] {
    m_encoder.encode(buffer: try m_converter.convert(buffer))
  }

  func dispose() { m_encoder.dispose() }
}
