#if os(macOS)

import CoreAudio
import XCTest

@testable import record_darwin

// Runs against the real devices of the Mac.
final class CoreAudioDevicesTests: XCTestCase {
  func testEachInputUidFindsItsDevice() {
    let inputs = CoreAudioDevices.captureDevices()
    XCTAssertFalse(inputs.isEmpty)

    for input in inputs {
      let deviceId = CoreAudioDevices.id(forUid: input.uniqueID)
      XCTAssertNotNil(deviceId, input.uniqueID)
      XCTAssertEqual(deviceId.flatMap(CoreAudioDevices.deviceUid(of:)), input.uniqueID)
    }
  }

  func testARawIdFindsItsDevice() throws {
    let uid = try XCTUnwrap(CoreAudioDevices.captureDevices().first?.uniqueID)
    let deviceId = try XCTUnwrap(CoreAudioDevices.id(forUid: uid))

    XCTAssertEqual(CoreAudioDevices.id(forUid: String(deviceId)), deviceId)
  }

  func testAnUnknownDeviceIsNotFound() {
    XCTAssertNil(CoreAudioDevices.id(forUid: "no.such.device"))
    XCTAssertNil(CoreAudioDevices.id(forUid: "999999"))
  }
}

#endif
