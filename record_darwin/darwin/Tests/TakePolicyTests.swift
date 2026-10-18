import XCTest

@testable import record_darwin

// Mirrors android's AudioInterruptionPolicyTest, plus the input changes.
final class TakePolicyTests: XCTestCase {
  private func react(
    _ mode: AudioInterruptionMode,
    _ event: EnvironmentEvent,
    pausedFor: PauseReason? = nil
  ) -> TakeAction? {
    TakePolicy.react(to: .environment(event), config: makeConfig(audioInterruption: mode), pausedFor: pausedFor)
  }

  private func stopInput(pausedFor: PauseReason? = nil) -> TakeAction? {
    TakePolicy.react(to: .inputStopped, config: makeConfig(), pausedFor: pausedFor)
  }

  // MARK: - Interruptions

  func testNoneIgnoresInterruption() {
    XCTAssertNil(react(AudioInterruptionMode.none, .interrupted))
    XCTAssertNil(react(AudioInterruptionMode.none, .interruptionEnded(shouldResume: true), pausedFor: .interruption))
  }

  // The take never paused, but the system stopped its capture during the interruption.
  // The app asked to go on recording, so we restart even when the system does not suggest it.
  func testNoneRestartsCaptureWhenTheInterruptionEnds() {
    XCTAssertEqual(react(AudioInterruptionMode.none, .interruptionEnded(shouldResume: true)), .restart)
    XCTAssertEqual(react(AudioInterruptionMode.none, .interruptionEnded(shouldResume: false)), .restart)
    XCTAssertNil(react(AudioInterruptionMode.none, .interruptionEnded(shouldResume: true), pausedFor: .user))
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

  // MARK: - Input changes

  // E.g. a headset was connected. The take goes on, on its own input.
  func testAStoppedInputRestartsWhileRecording() {
    XCTAssertEqual(stopInput(), .restart)
  }

  // Like an interruption: its end may resume the take.
  func testAFailedRestartPausesLikeAnInterruption() {
    let react = { TakePolicy.react(to: .restartFailed, config: makeConfig(), pausedFor: $0) }

    XCTAssertEqual(react(nil), .pause(.interruption))
    XCTAssertNil(react(.user))
  }

  // The take must not pause. The interruption end restarts it.
  func testAFailedRestartNeverPausesWithNone() {
    let config = makeConfig(audioInterruption: AudioInterruptionMode.none)
    XCTAssertNil(TakePolicy.react(to: .restartFailed, config: config, pausedFor: nil))
  }

  // resume() starts it again.
  func testAStoppedInputWaitsDuringAnyPause() {
    XCTAssertNil(stopInput(pausedFor: .user))
    XCTAssertNil(stopInput(pausedFor: .interruption))
  }
}
