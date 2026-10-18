#if os(iOS)

import AVFoundation
import XCTest

@testable import record_darwin

// Runs against the real audio session.
final class IosAudioEnvironmentTests: XCTestCase {
  private let session = AVAudioSession.sharedInstance()
  private var appCategory: AVAudioSession.Category!
  private var appOptions: AVAudioSession.CategoryOptions!
  private let environment = IosAudioEnvironment()

  override func setUp() {
    super.setUp()
    appCategory = session.category
    appOptions = session.categoryOptions
  }

  override func tearDown() {
    environment.release()
    try? session.setCategory(appCategory, options: appOptions)
    super.tearDown()
  }

  // During a pause, the app plays with its own category. resume() records with the take's options again.
  func testActivateSetsTheTakeCategoryAgain() throws {
    try environment.prepare(makeConfig(extra: ["iosConfig": ["categoryOptions": "mixWithOthers"]]))
    try session.setCategory(.playback)

    try environment.activate()

    XCTAssertEqual(session.category, .playAndRecord)
    XCTAssertEqual(session.categoryOptions, .mixWithOthers)
  }

  // The app sets the category itself.
  func testActivateKeepsTheAppCategoryWhenTheAppManagesTheSession() throws {
    environment.manageAudioSession = false
    try environment.prepare(makeConfig())
    try session.setCategory(.record)

    try environment.activate()

    XCTAssertEqual(session.category, .record)
  }
}

#endif
