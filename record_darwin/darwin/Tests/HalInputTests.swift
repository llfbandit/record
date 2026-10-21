#if os(macOS)

import AVFoundation
import XCTest

@testable import record_darwin

// Nothing here captures: that needs the mic permission. The Mac live tests capture.
final class HalInputTests: XCTestCase {
  func testMonoAndStereoGetOneFloatBufferPerChannel() throws {
    for channels in [1, 2] {
      let format = try XCTUnwrap(HalInput.format(sampleRate: 48000, channels: channels))

      XCTAssertEqual(format.sampleRate, 48000)
      XCTAssertEqual(format.channelCount, AVAudioChannelCount(channels))
      XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
      XCTAssertFalse(format.isInterleaved)
    }
  }

  // An audio interface can have many inputs. They need a channel layout.
  func testManyChannelsGetADiscreteLayout() throws {
    let format = try XCTUnwrap(HalInput.format(sampleRate: 44100, channels: 8))

    XCTAssertEqual(format.channelCount, 8)
    XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
    XCTAssertFalse(format.isInterleaved)
  }

  func testADeviceWithoutInputHasNoFormat() {
    XCTAssertNil(HalInput.format(sampleRate: 48000, channels: 0))
    XCTAssertNil(HalInput.format(sampleRate: 0, channels: 1))
  }

  // What HalInput captures in: each input of the Mac must give it.
  func testEachInputHasAFormat() throws {
    let inputs = CoreAudioDevices.captureDevices()
    XCTAssertFalse(inputs.isEmpty)

    for input in inputs {
      let deviceId = try XCTUnwrap(CoreAudioDevices.id(forUid: input.uniqueID))
      let rate = try XCTUnwrap(CoreAudioDevices.sampleRate(of: deviceId), input.uniqueID)
      let channels = CoreAudioDevices.inputChannels(of: deviceId)

      XCTAssertGreaterThan(rate, 0, input.uniqueID)
      XCTAssertGreaterThan(channels, 0, input.uniqueID)
      XCTAssertNotNil(HalInput.format(sampleRate: rate, channels: channels), input.uniqueID)
    }
  }

  // HalInput sets the unit's limit from it, so a big device buffer still records.
  func testEachInputHasAMaxBufferSize() throws {
    for input in CoreAudioDevices.captureDevices() {
      let deviceId = try XCTUnwrap(CoreAudioDevices.id(forUid: input.uniqueID))
      XCTAssertGreaterThan(try XCTUnwrap(CoreAudioDevices.maxBufferFrames(of: deviceId), input.uniqueID), 0, input.uniqueID)
    }
  }

  // It never binds another input instead.
  func testAnUnknownDeviceIsNoInputDevice() {
    XCTAssertThrowsError(try MacosInputRoute().bind("no.such.device", channels: 1)) { assertNoInputDevice($0) }
    XCTAssertThrowsError(
      try HalInput.open(on: "no.such.device", config: makeConfig(), onBuffer: { _ in }, onChange: {})
    ) { assertNoInputDevice($0) }
  }
}

#endif
