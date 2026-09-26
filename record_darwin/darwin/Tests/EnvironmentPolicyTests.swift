import XCTest

@testable import record_darwin

// Mirrors android's AudioInterruptionPolicyTest.
final class EnvironmentPolicyTests: XCTestCase {
  private func react(
    _ mode: AudioInterruptionMode,
    _ event: EnvironmentEvent
  ) -> PolicyAction? {
    EnvironmentPolicy.react(config: makeConfig(audioInterruption: mode), event: event)
  }

  func testNoneIgnoresInterruption() {
    XCTAssertNil(react(AudioInterruptionMode.none, .interrupted))
    XCTAssertNil(react(AudioInterruptionMode.none, .interruptionEnded(shouldResume: true)))
  }

  func testPausePausesButNeverResumes() {
    XCTAssertEqual(react(.pause, .interrupted), .pause)
    XCTAssertNil(react(.pause, .interruptionEnded(shouldResume: true)))
  }

  func testPauseResumePausesAndResumes() {
    XCTAssertEqual(react(.pauseResume, .interrupted), .pause)
    XCTAssertEqual(react(.pauseResume, .interruptionEnded(shouldResume: true)), .resume)
  }

  // The system says whether it wants the resume, and we obey it.
  func testPauseResumeStaysPausedWhenTheSystemSaysSo() {
    XCTAssertNil(react(.pauseResume, .interruptionEnded(shouldResume: false)))
  }

  // The policy keeps no state, so each call stands alone.
  func testPolicyIsStateless() {
    let config = makeConfig(audioInterruption: .pauseResume)

    XCTAssertEqual(EnvironmentPolicy.react(config: config, event: .interrupted), .pause)
    XCTAssertEqual(EnvironmentPolicy.react(config: config, event: .interrupted), .pause)
    XCTAssertEqual(
      EnvironmentPolicy.react(config: config, event: .interruptionEnded(shouldResume: true)),
      .resume
    )
  }
}
