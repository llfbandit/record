#if os(iOS)

import AVFoundation
import XCTest

@testable import record_darwin

// Runs against the real audio session.
final class IosDeviceRegistryTests: XCTestCase {
  private let session = AVAudioSession.sharedInstance()
  private var appCategory: AVAudioSession.Category!

  override func setUp() {
    super.setUp()
    appCategory = session.category
  }

  override func tearDown() {
    try? session.setCategory(appCategory)
    super.tearDown()
  }

  // During a pause, the app plays with its own category. We must not change it.
  func testIsAvailableKeepsTheAppCategory() throws {
    try session.setCategory(.playback)

    XCTAssertTrue(IosDeviceRegistry().isAvailable("gone-mic"))
    XCTAssertEqual(session.category, .playback)
  }

  func testIsAvailableSeesAMissingInput() throws {
    try session.setCategory(.playAndRecord)

    XCTAssertFalse(IosDeviceRegistry().isAvailable("gone-mic"))
  }
}

#endif
