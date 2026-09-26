import AVFoundation
import XCTest

@testable import record_darwin

// The input format stands for what the capture graph gives.
final class FormatPolicyTests: XCTestCase {
  private func input(channels: AVAudioChannelCount, sampleRate: Double = 48000) -> AVAudioFormat {
    AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
  }

  private func pcm(channels: AVAudioChannelCount, sampleRate: Double = 44100) -> AVAudioFormat {
    AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: false)!
  }

  // MARK: - Channels and rates

  func testChannelsAreClampedToTheInput() throws {
    let (settings, effective) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "pcm16bits", numChannels: 2), input: input(channels: 1))

    XCTAssertEqual(effective.numChannels, 1)
    XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
  }

  func testChannelsAreNotRaisedToTheInput() throws {
    let (_, effective) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "pcm16bits", numChannels: 1), input: input(channels: 2))

    XCTAssertEqual(effective.numChannels, 1)
  }

  // A graph with no input yet reports zeros. That must not clamp anything.
  func testNoInputKeepsWhatWasAsked() throws {
    let (_, effective) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 2), input: AVAudioFormat())

    XCTAssertEqual(effective.numChannels, 2)
    XCTAssertEqual(effective.sampleRate, 16000)
  }

  // PCM is resampled by us, so any rate is fine.
  func testPcmKeepsTheRequestedRate() throws {
    let (settings, effective) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 1), input: input(channels: 1))

    XCTAssertEqual(effective.sampleRate, 16000)
    XCTAssertEqual(settings[AVFormatIDKey] as? UInt32, kAudioFormatLinearPCM)
  }

  func testAacIsPinnedToARateItsEncoderSupports() throws {
    let (settings, effective) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "aacLc", sampleRate: 44100, numChannels: 1), input: input(channels: 1))

    XCTAssertEqual(settings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
    // The encoder decides, so only sanity is checked here.
    XCTAssertGreaterThan(effective.sampleRate, 0)
    XCTAssertGreaterThan(effective.bitRate, 0)
  }

  // Darwin has no AMR encoder.
  func testAnUnsupportedEncoderThrows() {
    XCTAssertThrowsError(
      try FormatPolicy.negotiate(for: makeConfig(encoder: "amrNb"), input: input(channels: 1)))
  }

  // iOS cannot encode HE v2, so stereo stays on HE v1.
  func testAacHeIsV1EvenInStereo() throws {
    let (settings, effective) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "aacHe", bitRate: 64000, numChannels: 2), input: input(channels: 2))

    XCTAssertEqual(settings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC_HE)
    XCTAssertEqual(effective.numChannels, 2)
  }

  // MARK: - Bit rates the encoder accepts

  // 320k is fine in stereo, but mono AAC refuses it.
  func testAacRefusesABitRateTooHighForMono() {
    let config = makeConfig(encoder: "aacLc", bitRate: 320000, sampleRate: 44100, numChannels: 1)

    XCTAssertThrowsError(try AacAdtsEncoder(config: config, format: pcm(channels: 1)))
  }

  func testATooHighBitRateIsLoweredToOneTheEncoderAccepts() throws {
    let (_, effective) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "aacLc", bitRate: 320000, sampleRate: 44100, numChannels: 2),
      input: input(channels: 1))

    XCTAssertEqual(effective.numChannels, 1)
    XCTAssertLessThan(effective.bitRate, 320000)
    XCTAssertNoThrow(try AacAdtsEncoder(config: effective, format: pcm(channels: 1)))
  }

  // Too low is refused too. Stereo AAC starts well above 16k.
  func testATooLowBitRateIsRaisedToOneTheEncoderAccepts() throws {
    let (_, effective) = try FormatPolicy.negotiate(
      for: makeConfig(encoder: "aacLc", bitRate: 16000, sampleRate: 44100, numChannels: 2),
      input: input(channels: 2, sampleRate: 44100))

    XCTAssertGreaterThan(effective.bitRate, 16000)
    XCTAssertNoThrow(try AacAdtsEncoder(config: effective, format: pcm(channels: 2)))
  }

  // MARK: - File containers

  // The container follows the encoder. The path extension is not read.
  func testEachEncoderGetsItsContainer() {
    XCTAssertEqual(FormatPolicy.fileType(for: "aacLc"), kAudioFileM4AType)
    XCTAssertEqual(FormatPolicy.fileType(for: "aacEld"), kAudioFileM4AType)
    XCTAssertEqual(FormatPolicy.fileType(for: "aacHe"), kAudioFileM4AType)
    XCTAssertEqual(FormatPolicy.fileType(for: "opus"), kAudioFileCAFType)
    XCTAssertEqual(FormatPolicy.fileType(for: "flac"), kAudioFileFLACType)
    XCTAssertEqual(FormatPolicy.fileType(for: "wav"), kAudioFileWAVEType)
  }

  // pcm16bits is raw samples with no header, like Android writes it.
  func testPcm16bitsHasNoContainer() {
    XCTAssertNil(FormatPolicy.fileType(for: "pcm16bits"))
  }
}
