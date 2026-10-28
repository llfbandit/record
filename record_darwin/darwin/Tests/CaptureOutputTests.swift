import AVFoundation
import XCTest

@testable import record_darwin

// Writes a tone through each file output, then reads the file back.
final class CaptureOutputTests: XCTestCase {
  private let rate = 48000.0
  private var paths: [String] = []

  override func tearDown() {
    for path in paths { try? FileManager.default.removeItem(atPath: path) }
    super.tearDown()
  }

  private func path(_ name: String) -> String {
    let path = NSTemporaryDirectory() + "capture_output_\(name)"
    try? FileManager.default.removeItem(atPath: path)
    paths.append(path)
    return path
  }

  // Like a tap buffer: Float32, not interleaved.
  private var captureFormat: AVAudioFormat {
    AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
  }

  // What a Bluetooth headset gives: 16 kHz, but stereo to test the channel change too.
  private let headsetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 2, interleaved: false)!

  // Writes `seconds` of a 440 Hz tone, in tap-sized buffers of 0.1 s.
  private func write(_ seconds: Double, to output: CaptureOutput, format: AVAudioFormat? = nil) throws {
    let format = format ?? captureFormat
    let frames = AVAudioFrameCount(format.sampleRate / 10)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    var phase: Float = 0
    for _ in 0..<Int(seconds * 10) {
      for i in 0..<Int(frames) {
        for channel in 0..<Int(format.channelCount) { buffer.floatChannelData![channel][i] = 0.5 * sin(phase) }
        phase += 2 * .pi * 440 / Float(format.sampleRate)
      }
      try output.write(buffer)
    }
  }

  private func fileOutput(_ encoder: String, _ name: String) throws -> (AudioFileOutput, String) {
    let (settings, config) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: encoder, sampleRate: Int(rate), numChannels: 1), input: captureFormat)
    let path = path(name)
    let output = try AudioFileOutput(
      path: path, settings: settings, fileType: FormatPolicy.fileType(for: config.encoder)!, srcFormat: captureFormat)
    return (output, path)
  }

  private func rawOutput(_ config: RecordConfig, _ name: String) throws -> (RawFileOutput, String) {
    let path = path(name)
    return (try RawFileOutput(path: path, processor: AudioStreamProcessor(config: config, srcFormat: captureFormat)), path)
  }

  private func duration(_ path: String) -> Double {
    guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return -1 }
    return Double(file.length) / file.fileFormat.sampleRate
  }

  private func size(_ path: String) -> Int {
    FileManager.default.contents(atPath: path)?.count ?? 0
  }

  private func header(_ path: String, at offset: Int = 0) -> String {
    let bytes = FileManager.default.contents(atPath: path)?.dropFirst(offset).prefix(4) ?? Data()
    return String(decoding: bytes, as: UTF8.self)
  }

  // MARK: - AVAudioFile

  func testAacGoesIntoAnM4aFile() throws {
    let (output, path) = try fileOutput("aacLc", "aac.m4a")

    try write(2, to: output)
    XCTAssertEqual(output.close(delete: false), path)

    XCTAssertEqual(duration(path), 2, accuracy: 0.05)
  }

  func testAacHeGoesIntoAnM4aFile() throws {
    let (output, path) = try fileOutput("aacHe", "he.m4a")

    try write(1, to: output)
    _ = output.close(delete: false)

    XCTAssertEqual(header(path, at: 4), "ftyp")
    XCTAssertEqual(duration(path), 1, accuracy: 0.05)
  }

  // Like an interruption. A pause, then more audio in the same file.
  func testWritingAgainAppendsToTheSameFile() throws {
    let (output, path) = try fileOutput("aacLc", "append.m4a")

    try write(1, to: output)
    try write(1, to: output)
    _ = output.close(delete: false)

    XCTAssertEqual(duration(path), 2, accuracy: 0.05)
  }

  // Like a route change. The input changes its format, and the file goes on in its own.
  func testAFileGoesOnWhenTheInputChangesItsFormat() throws {
    let (output, path) = try fileOutput("wav", "moved.wav")

    try write(1, to: output)
    try output.setInputFormat(headsetFormat)
    try write(1, to: output, format: headsetFormat)
    _ = output.close(delete: false)

    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    XCTAssertEqual(file.fileFormat.sampleRate, rate)
    XCTAssertEqual(file.fileFormat.channelCount, 1)
    // The resamplers hold back a few frames.
    XCTAssertEqual(duration(path), 2, accuracy: 0.05)
  }

  func testWavHasItsHeader() throws {
    let (output, path) = try fileOutput("wav", "take.wav")

    try write(1, to: output)
    _ = output.close(delete: false)

    XCTAssertEqual(header(path), "RIFF")
    XCTAssertEqual(duration(path), 1, accuracy: 0.01)
  }

  func testFlacIsANativeFlacFile() throws {
    let (output, path) = try fileOutput("flac", "take.flac")

    try write(1, to: output)
    _ = output.close(delete: false)

    XCTAssertEqual(header(path), "fLaC")
    XCTAssertEqual(duration(path), 1, accuracy: 0.01)
  }

  // A .opus path still gets CAF, the only container Apple writes Opus in.
  func testOpusIsWrittenInCafWhateverThePathSays() throws {
    let (output, path) = try fileOutput("opus", "take.opus")

    try write(1, to: output)
    _ = output.close(delete: false)

    XCTAssertEqual(header(path), "caff")
  }

  func testCloseWithDeleteRemovesTheFile() throws {
    let (output, path) = try fileOutput("aacLc", "cancel.m4a")

    try write(1, to: output)

    XCTAssertNil(output.close(delete: true))
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
  }

  func testAFailedSetupLeavesNoFile() throws {
    let (settings, config) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "aacLc", sampleRate: Int(rate), numChannels: 1), input: captureFormat)
    let path = path("failed.m4a")

    // The converter refuses an empty format.
    XCTAssertThrowsError(try AudioFileOutput(
      path: path, settings: settings, fileType: FormatPolicy.fileType(for: config.encoder)!, srcFormat: AVAudioFormat()))
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
  }

  // MARK: - Raw PCM

  // 16 bit mono at 16 kHz: 32000 bytes per second, and no header.
  func testPcm16bitsIsRawSamples() throws {
    let (output, path) = try rawOutput(makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 1), "take.pcm")

    try write(1, to: output)
    XCTAssertEqual(output.close(delete: false), path)

    // The resampler holds back a few frames.
    XCTAssertEqual(Double(size(path)), 32000, accuracy: 32000 * 0.02)
    XCTAssertNotEqual(header(path), "RIFF")
  }

  // A stream, or a raw file, keeps its format when the input changes.
  func testRawPcmGoesOnWhenTheInputChangesItsFormat() throws {
    let (output, path) = try rawOutput(makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 1), "moved.pcm")

    try write(1, to: output)
    try output.setInputFormat(headsetFormat)
    try write(1, to: output, format: headsetFormat)
    _ = output.close(delete: false)

    XCTAssertEqual(Double(size(path)), 64000, accuracy: 64000 * 0.02)
  }

  // MARK: - Inputs with many channels

  // What an audio interface gives: 4 discrete channels. A tone at 0.5 in the first, at 0.25 in the second.
  private func discreteBuffer() -> AVAudioPCMBuffer {
    let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 4)!
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, interleaved: false, channelLayout: layout)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
    buffer.frameLength = 4800
    for channel in 0..<4 {
      let amplitude: Float = [0.5, 0.25, 0, 0][channel]
      for i in 0..<4800 { buffer.floatChannelData![channel][i] = amplitude * sin(2 * .pi * 440 * Float(i) / Float(rate)) }
    }
    return buffer
  }

  // The loudest sample of each channel, in 16 bit interleaved data.
  private func peaks(_ data: Data, channels: Int) -> [Int] {
    let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    return (0..<channels).map { channel in
      stride(from: channel, to: samples.count, by: channels).map { Int(samples[$0].magnitude) }.max() ?? 0
    }
  }

  func testAMonoStreamTakesTheFirstOfManyChannels() throws {
    let buffer = discreteBuffer()
    let config = makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 1)
    let processor = try AudioStreamProcessor(config: config, srcFormat: buffer.format)

    let peak = peaks(try processor.process(buffer: buffer).reduce(Data(), +), channels: 1)[0]
    // 0.5 of full scale: the first channel, alone.
    XCTAssertEqual(Double(peak), 16384, accuracy: 1000)
  }

  func testAStereoStreamTakesTheFirstTwoOfManyChannels() throws {
    let buffer = discreteBuffer()
    let config = makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 2)
    let processor = try AudioStreamProcessor(config: config, srcFormat: buffer.format)

    let peaks = peaks(try processor.process(buffer: buffer).reduce(Data(), +), channels: 2)
    XCTAssertEqual(Double(peaks[0]), 16384, accuracy: 1000)
    XCTAssertEqual(Double(peaks[1]), 8192, accuracy: 1000)
  }

  func testAStereoAacStreamKeepsItsChannels() throws {
    let buffer = discreteBuffer()
    let config = makeConfig(encoder: "aacLc", sampleRate: Int(rate), numChannels: 2)
    let processor = try AudioStreamProcessor(config: config, srcFormat: buffer.format)

    var chunks: [Data] = []
    for _ in 0..<10 { chunks += try processor.process(buffer: buffer) }
    processor.dispose()

    // One ADTS packet per chunk.
    XCTAssertFalse(chunks.isEmpty)
    for chunk in chunks {
      XCTAssertEqual(chunk.prefix(2), Data([0xFF, 0xF1]))
      let size = (Int(chunk[3]) & 0x3) << 11 | Int(chunk[4]) << 3 | Int(chunk[5]) >> 5
      XCTAssertEqual(size, chunk.count)
    }

    let path = path("stream.aac")
    FileManager.default.createFile(atPath: path, contents: chunks.reduce(Data(), +))
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: read)

    XCTAssertEqual(read.format.channelCount, 2)
    let peaks = (0..<2).map { channel in
      UnsafeBufferPointer(start: read.floatChannelData![channel], count: Int(read.frameLength)).map(abs).max() ?? 0
    }
    XCTAssertEqual(Double(peaks[0]), 0.5, accuracy: 0.05)
    XCTAssertEqual(Double(peaks[1]), 0.25, accuracy: 0.05)
  }

  func testAFileTakesTheFirstOfManyChannels() throws {
    let buffer = discreteBuffer()
    let (settings, config) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "wav", sampleRate: Int(rate), numChannels: 1), input: buffer.format)
    let path = path("discrete.wav")
    let output = try AudioFileOutput(
      path: path, settings: settings, fileType: FormatPolicy.fileType(for: config.encoder)!, srcFormat: buffer.format)

    for _ in 0..<5 { try output.write(buffer) }
    _ = output.close(delete: false)

    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: read)
    let samples = UnsafeBufferPointer(start: read.floatChannelData![0], count: Int(read.frameLength))
    XCTAssertEqual(Double(samples.map(abs).max() ?? 0), 0.5, accuracy: 0.05)
  }
}
