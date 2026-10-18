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

  // A private aggregate, like the one voice processing makes, is not an input for the app. A public one is.
  func testOnlyPublicAggregatesAreListed() throws {
    let inputUid = try XCTUnwrap(CoreAudioDevices.captureDevices().first?.uniqueID)

    for isPrivate in [true, false] {
      let uid = "record.test.aggregate.\(isPrivate ? "private" : "public")"
      let aggregate = makeAggregate(uid, around: inputUid, isPrivate: isPrivate)
      let listed = CoreAudioDevices.captureDevices().contains { $0.uniqueID == uid }
      destroy(aggregate, uid: uid)

      XCTAssertEqual(listed, !isPrivate, uid)
    }
  }

  // CoreAudio drops it a moment after. Other tests read the list.
  private func destroy(_ aggregate: AudioDeviceID, uid: String) {
    AudioHardwareDestroyAggregateDevice(aggregate)
    let end = Date().addingTimeInterval(3)
    while Date() < end, CoreAudioDevices.captureDevices().contains(where: { $0.uniqueID == uid }) {
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
  }

  private func makeAggregate(_ uid: String, around inputUid: String, isPrivate: Bool) -> AudioDeviceID {
    let desc: [String: Any] = [
      kAudioAggregateDeviceUIDKey: uid,
      kAudioAggregateDeviceNameKey: "Record test",
      kAudioAggregateDeviceIsPrivateKey: isPrivate ? 1 : 0,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: inputUid]],
    ]
    var aggregate = AudioDeviceID(0)
    XCTAssertEqual(AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggregate), noErr)
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    return aggregate
  }

  func testAnUnknownDeviceIsNotFound() {
    XCTAssertNil(CoreAudioDevices.id(forUid: "no.such.device"))
    XCTAssertNil(CoreAudioDevices.id(forUid: "999999"))
  }
}

#endif
