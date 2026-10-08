import XCTest

@testable import record_darwin

// Mirrors android's AudioInterruptionPolicyTest.
final class TakePolicyTests: XCTestCase {
  private func react(
    _ mode: AudioInterruptionMode,
    _ event: EnvironmentEvent,
    pausedFor: PauseReason? = nil
  ) -> TakeAction? {
    TakePolicy.react(to: event, config: makeConfig(audioInterruption: mode), pausedFor: pausedFor)
  }

  func testNoneIgnoresInterruption() {
    XCTAssertNil(react(AudioInterruptionMode.none, .interrupted))
    XCTAssertNil(react(AudioInterruptionMode.none, .interruptionEnded(shouldResume: true), pausedFor: .interruption))
  }

  func testPausePausesButNeverResumes() {
    XCTAssertEqual(react(.pause, .interrupted), .pause(.interruption))
    XCTAssertNil(react(.pause, .interruptionEnded(shouldResume: true), pausedFor: .interruption))
  }

  func testPauseResumePausesAndResumes() {
    XCTAssertEqual(react(.pauseResume, .interrupted), .pause(.interruption))
    XCTAssertEqual(react(.pauseResume, .interruptionEnded(shouldResume: true), pausedFor: .interruption), .resume)
  }

  // The system says whether it wants the resume, and we obey it.
  func testPauseResumeStaysPausedWhenTheSystemSaysSo() {
    XCTAssertNil(react(.pauseResume, .interruptionEnded(shouldResume: false), pausedFor: .interruption))
  }

  // An interruption end resumes only what the interruption paused.
  func testAnInterruptionEndLeavesOtherPausesAlone() {
    XCTAssertNil(react(.pauseResume, .interruptionEnded(shouldResume: true), pausedFor: .user))
    XCTAssertNil(react(.pauseResume, .interruptionEnded(shouldResume: true)))
  }

  // A paused take keeps its reason, so the interruption end cannot resume it.
  func testAnInterruptionDuringAPauseChangesNothing() {
    XCTAssertNil(react(.pauseResume, .interrupted, pausedFor: .user))
  }
}
