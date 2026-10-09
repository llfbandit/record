import AVFoundation

// Sends the captured audio to Dart or to a file.
// Called under the capture lock, so never from two threads at once.
protocol CaptureOutput: AnyObject {
  // Takes one tap buffer, in the capture format.
  func write(_ buffer: AVAudioPCMBuffer) throws

  // The capture moved to an input with this format. The output format stays the same.
  func setInputFormat(_ format: AVAudioFormat) throws

  // Frees everything. Returns the file, if there is one.
  func close(delete: Bool) -> String?
}

// Sends encoded chunks to Dart.
final class StreamOutput: CaptureOutput {
  private let m_processor: AudioStreamProcessor
  private let m_onChunk: (Data) -> Void

  init(processor: AudioStreamProcessor, onChunk: @escaping (Data) -> Void) {
    m_processor = processor
    m_onChunk = onChunk
  }

  func write(_ buffer: AVAudioPCMBuffer) throws {
    for chunk in try m_processor.process(buffer: buffer) { m_onChunk(chunk) }
  }

  func setInputFormat(_ format: AVAudioFormat) throws {
    try m_processor.setInputFormat(format)
  }

  func close(delete: Bool) -> String? {
    m_processor.dispose()
    return nil
  }
}

// Writes the file with AVAudioFile, which encodes it.
final class AudioFileOutput: CaptureOutput {
  private let m_path: String
  private var m_converter: AVAudioConverter
  private var m_file: AVAudioFile?

  init(path: String, settings: [String: Any], fileType: AudioFileTypeID, srcFormat: AVAudioFormat) throws {
    // The container comes from the encoder, never from the path extension.
    var settings = settings
    settings[AVAudioFileTypeKey] = fileType

    let file = try RecorderError.wrapping("AVAudioFile") {
      try AVAudioFile(
        forWriting: URL(fileURLWithPath: path),
        settings: settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
      )
    }

    do {
      m_converter = try AVAudioConverter.make(from: srcFormat, to: file.processingFormat)
    } catch {
      // The file is already on disk. Do not leave it there.
      try? RecordFile.delete(at: path)
      throw error
    }
    m_path = path
    m_file = file
  }

  func write(_ buffer: AVAudioPCMBuffer) throws {
    guard let file = m_file, m_converter.accepts(buffer) else { return }

    let converted = try m_converter.convert(buffer)
    try RecorderError.wrapping("AVAudioFile.write", failure: "Recording stopped") {
      try file.write(from: converted)
    }
  }

  func setInputFormat(_ format: AVAudioFormat) throws {
    m_converter = try m_converter.withInput(format)
  }

  func close(delete: Bool) -> String? {
    // Dropping the file closes it and writes the header.
    m_file = nil

    if delete {
      try? RecordFile.delete(at: m_path)
      return nil
    }
    return m_path
  }
}

// Raw PCM 16 bit, no header. The same bytes as a pcm16bits stream.
final class RawFileOutput: CaptureOutput {
  private let m_path: String
  private let m_processor: AudioStreamProcessor
  private let m_file: OutputStream

  init(path: String, processor: AudioStreamProcessor) throws {
    guard let file = OutputStream(toFileAtPath: path, append: false) else {
      throw RecorderError.startFailed("Cannot create the file.")
    }
    file.open()
    if let error = file.streamError {
      throw RecorderError.startFailed("Cannot open the file: \(error.localizedDescription)")
    }

    m_path = path
    m_processor = processor
    m_file = file
  }

  func write(_ buffer: AVAudioPCMBuffer) throws {
    for chunk in try m_processor.process(buffer: buffer) where !chunk.isEmpty {
      try writeAll(chunk)
    }
  }

  func setInputFormat(_ format: AVAudioFormat) throws {
    try m_processor.setInputFormat(format)
  }

  func close(delete: Bool) -> String? {
    m_file.close()
    m_processor.dispose()

    if delete {
      try? RecordFile.delete(at: m_path)
      return nil
    }
    return m_path
  }

  // A stream may write less than asked, so we loop.
  private func writeAll(_ data: Data) throws {
    try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
      let base = bytes.bindMemory(to: UInt8.self).baseAddress!
      var offset = 0
      while offset < data.count {
        let written = m_file.write(base + offset, maxLength: data.count - offset)
        guard written > 0 else {
          throw RecorderError.error(
            message: "Recording stopped",
            details: "Cannot write the file: \(m_file.streamError?.localizedDescription ?? "unknown error")"
          )
        }
        offset += written
      }
    }
  }
}

extension AVAudioFormat {
  // PCM 16 bit, not interleaved: what our encoders read.
  static func int16(sampleRate: Double, channels: Int) throws -> AVAudioFormat {
    guard let format = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: sampleRate,
      channels: AVAudioChannelCount(channels),
      interleaved: false
    ) else {
      throw RecorderError.startFailed("Format is not supported: \(Int(sampleRate))Hz - \(channels) channels.")
    }
    return format
  }
}

extension AVAudioConverter {
  static func make(from input: AVAudioFormat, to output: AVAudioFormat) throws -> AVAudioConverter {
    guard let converter = AVAudioConverter(from: input, to: output) else {
      throw RecorderError.startFailed("Format conversion is not possible.")
    }
    converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
    return converter
  }

  // False for a late buffer from the old input, after a move. We drop it.
  func accepts(_ buffer: AVAudioPCMBuffer) -> Bool {
    buffer.format.sampleRate == inputFormat.sampleRate && buffer.format.channelCount == inputFormat.channelCount
  }

  // The same output, from another input.
  func withInput(_ format: AVAudioFormat) throws -> AVAudioConverter {
    try .make(from: format, to: outputFormat)
  }

  // Converts one whole tap buffer.
  func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    let capacity = AVAudioFrameCount(
      Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
    )
    guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      throw Self.conversionFailed
    }

    var provided = false
    var error: NSError?
    convert(to: out, error: &error) { _, outStatus in
      if provided {
        outStatus.pointee = .noDataNow
        return nil
      }
      provided = true
      outStatus.pointee = .haveData
      return buffer
    }
    guard error == nil else { throw Self.conversionFailed }
    return out
  }

  private static let conversionFailed = RecorderError.error(
    message: "Recording stopped", details: "Audio format conversion failed.")
}
