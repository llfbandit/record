import XCTest

@testable import record_darwin

final class RecordConfigTests: XCTestCase {
  func testMissingEncoderThrows() {
    XCTAssertThrowsError(try RecordConfig.fromMap(["sampleRate": 8000]))
  }

  func testMissingKeysKeepTheDefaults() throws {
    let config = try RecordConfig.fromMap(["encoder": "aacLc"])

    XCTAssertEqual(config.bitRate, 128000)
    XCTAssertEqual(config.sampleRate, 44100)
    XCTAssertEqual(config.numChannels, 2)
    XCTAssertEqual(config.audioInterruption, .pause)
    XCTAssertNil(config.device)
    XCTAssertNil(config.streamBufferSize)
  }

  // The old macOS code force unwrapped these and crashed.
  func testADeviceWithoutAnIdIsDropped() throws {
    let config = try RecordConfig.fromMap([
      "encoder": "aacLc",
      "device": ["label": "Mic"],
    ])

    XCTAssertNil(config.device)
  }

  func testADeviceIsRead() throws {
    let config = try RecordConfig.fromMap([
      "encoder": "aacLc",
      "device": ["id": "mic-1", "label": "Mic", "type": "usb", "sampleRates": [16000, 48000]],
    ])

    XCTAssertEqual(config.device?.id, "mic-1")
    XCTAssertEqual(config.device?.type, "usb")
    XCTAssertEqual(config.device?.sampleRates, [16000, 48000])
  }

  func testToMapKeepsTheCallArgumentsAndOverridesWhatWasNegotiated() {
    let config = makeConfig(sampleRate: 44100, extra: ["iosConfig": ["allowHaptics": true]])
    let map = config.negotiated(sampleRate: 48000, bitRate: 96000, numChannels: 1).toMap()

    XCTAssertEqual(map["sampleRate"] as? Int, 48000)
    XCTAssertEqual(map["bitRate"] as? Int, 96000)
    XCTAssertEqual(map["numChannels"] as? Int, 1)
    // A platform key the shared config never reads still survives the round trip.
    XCTAssertNotNil(map["iosConfig"])
  }

  func testNegotiatedLeavesTheOriginalAlone() {
    let config = makeConfig(sampleRate: 44100, numChannels: 2)
    _ = config.negotiated(sampleRate: 8000, bitRate: 16000, numChannels: 1)

    XCTAssertEqual(config.sampleRate, 44100)
    XCTAssertEqual(config.numChannels, 2)
  }

  func testIsModifiedOnlyWhenAValueChanged() {
    let config = makeConfig(bitRate: 128000, sampleRate: 44100, numChannels: 2)

    XCTAssertFalse(config.negotiated(sampleRate: 44100, bitRate: 128000, numChannels: 2).isModified(from: config))
    XCTAssertTrue(config.negotiated(sampleRate: 48000, bitRate: 128000, numChannels: 2).isModified(from: config))
    XCTAssertTrue(config.negotiated(sampleRate: 44100, bitRate: 96000, numChannels: 2).isModified(from: config))
    XCTAssertTrue(config.negotiated(sampleRate: 44100, bitRate: 128000, numChannels: 1).isModified(from: config))
  }

  // Dart reads a missing device as "the default input".
  func testTheDefaultDeviceIsReportedAsNoDevice() {
    let config = makeConfig(device: Device(id: "usb-mic", label: "USB mic"))
    let fallback = config.withDefaultDevice()

    XCTAssertTrue(fallback.isModified(from: config))
    XCTAssertNil(fallback.toMap()["device"])
    XCTAssertNotNil(config.toMap()["device"])
  }
}
