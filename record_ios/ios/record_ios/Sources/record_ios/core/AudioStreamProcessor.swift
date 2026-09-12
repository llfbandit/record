import AVFoundation

/// Processes the audio of a stream recording:
/// PCM conversion, amplitude, and encoding (AAC or PCM16).
class AudioStreamProcessor {
  private let m_converter: AVAudioConverter
  private let m_encoder: AudioEnc
  private var m_amplitude: Float = silenceDb

  init(config: RecordConfig, srcFormat: AVAudioFormat) throws {
    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(config.sampleRate),
      channels: AVAudioChannelCount(config.numChannels),
      interleaved: false
    ) else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format is not supported: \(config.sampleRate)Hz - \(config.numChannels) channels."
      )
    }

    guard let converter = AVAudioConverter(from: srcFormat, to: outputFormat) else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format conversion is not possible."
      )
    }
    converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
    m_converter = converter

    if config.encoder == AudioEncoder.aacLc.rawValue {
      let aac = AacAdtsEncoder()
      try aac.setup(config: config, format: outputFormat)
      m_encoder = aac
    } else if config.encoder == AudioEncoder.pcm16bits.rawValue {
      m_encoder = Pcm16BitsEncoder()
    } else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Encoder '\(config.encoder)' is not supported for stream recording."
      )
    }
  }

  /// Converts, tracks amplitude, and encodes one tap buffer.
  /// Returns `nil` if conversion fails for good. The caller must stop recording.
  /// Returns `[]` while the encoder waits for more data (AAC needs a full frame).
  func process(buffer: AVAudioPCMBuffer) -> [Data]? {
    guard let converted = convertBuffer(buffer) else { return nil }
    updateAmplitude(converted)
    return m_encoder.encode(buffer: converted)
  }

  func getAmplitude() -> Float { m_amplitude }

  func dispose() { m_encoder.dispose() }

  // MARK: - Private

  private func convertBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    let capacity = AVAudioFrameCount(
      Double(buffer.frameLength) * m_converter.outputFormat.sampleRate / buffer.format.sampleRate
    )
    guard let out = AVAudioPCMBuffer(pcmFormat: m_converter.outputFormat, frameCapacity: capacity) else {
      return nil
    }
    var provided = false
    let inputCallback: AVAudioConverterInputBlock = { _, outStatus in
      if provided {
        outStatus.pointee = .noDataNow
        return nil
      }
      provided = true
      outStatus.pointee = .haveData
      return buffer
    }
    var error: NSError?
    m_converter.convert(to: out, error: &error, withInputFrom: inputCallback)
    if error != nil { return nil }
    return out
  }

  private func updateAmplitude(_ buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.int16ChannelData else { return }
    let frameCount = Int(buffer.frameLength)
    var maxSample: Float = 0
    let ch0 = channelData[0]
    for i in 0..<frameCount {
      let s = abs(Float(ch0[i]))
      if s > maxSample { maxSample = s }
    }
    m_amplitude = maxSample > 0 ? 20 * log10(maxSample / 32767.0) : silenceDb
  }
}
