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

  // After a move, the old engine can still send a buffer. It is dropped, not an error.
  func testAFileDropsABufferFromTheOldInput() throws {
    let (output, path) = try fileOutput("wav", "late.wav")

    try write(1, to: output)
    try output.setInputFormat(headsetFormat)
    try write(0.1, to: output)
    try write(1, to: output, format: headsetFormat)
    _ = output.close(delete: false)

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

    let size = FileManager.default.contents(atPath: path)?.count ?? 0
    // The resampler holds back a few frames.
    XCTAssertEqual(Double(size), 32000, accuracy: 32000 * 0.02)
    XCTAssertNotEqual(header(path), "RIFF")
  }

  // A stream, or a raw file, keeps its format when the input changes.
  func testRawPcmGoesOnWhenTheInputChangesItsFormat() throws {
    let (output, path) = try rawOutput(makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 1), "moved.pcm")

    try write(1, to: output)
    try output.setInputFormat(headsetFormat)
    try write(1, to: output, format: headsetFormat)
    _ = output.close(delete: false)

    let size = FileManager.default.contents(atPath: path)?.count ?? 0
    XCTAssertEqual(Double(size), 64000, accuracy: 64000 * 0.02)
  }

  func testRawPcmDropsABufferFromTheOldInput() throws {
    let (output, path) = try rawOutput(makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 1), "late.pcm")

    try write(1, to: output)
    try output.setInputFormat(headsetFormat)
    try write(0.1, to: output)
    try write(1, to: output, format: headsetFormat)
    _ = output.close(delete: false)

    let size = FileManager.default.contents(atPath: path)?.count ?? 0
    XCTAssertEqual(Double(size), 64000, accuracy: 64000 * 0.02)
  }
}
