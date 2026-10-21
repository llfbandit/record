import XCTest

@testable import record_darwin

// Mirrors android's RecorderControllerTest.
final class RecorderControllerTests: XCTestCase {
  private var h = ControllerHarness()
  private let usbMic = Device(id: "usb-mic", label: "USB mic")

  override func setUp() {
    super.setUp()
    h = ControllerHarness()
  }

  // MARK: - Start

  func testStartPreparesTheEnvironmentThenTheEngineAndReportsRecord() throws {
    try h.startRecording()

    h.run {
      XCTAssertEqual(h.platform.fakeEnvironment.prepareCount, 1)
      XCTAssertEqual(h.platform.lastEngine?.startCount, 1)
      XCTAssertEqual(h.sink.states, [.record])
      XCTAssertTrue(h.controller.isRecording)
      XCTAssertFalse(h.controller.isPaused)
    }
  }

  func testAnUnsupportedEncoderNeverReachesTheEnvironment() {
    XCTAssertThrowsError(try h.startRecording(makeConfig(encoder: "opus")))

    h.run {
      XCTAssertEqual(h.platform.fakeEnvironment.prepareCount, 0)
      XCTAssertEqual(h.platform.fileEngineCount, 0)
      XCTAssertEqual(h.sink.states, [])
    }
  }

  func testAFailedEnvironmentNeverBuildsAnEngine() {
    h.platform.fakeEnvironment.prepareError = TestError.boom

    XCTAssertThrowsError(try h.startRecording())

    h.run {
      XCTAssertEqual(h.platform.fileEngineCount, 0)
      XCTAssertEqual(h.sink.states, [])
      XCTAssertFalse(h.controller.isRecording)
    }
  }

  // A failed start leaves nothing behind. No session, no engine, no environment.
  func testAFailedEngineStartLeavesNothingBehind() {
    h.platform.prepareEngine = { $0.startError = TestError.boom }

    XCTAssertThrowsError(try h.startRecording()) { XCTAssertEqual($0 as? TestError, .boom) }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.stopDeleteFlags, [true])
      XCTAssertEqual(h.platform.fakeEnvironment.releaseCount, 1)
      XCTAssertEqual(h.sink.states, [])
      XCTAssertFalse(h.controller.isRecording)
    }
  }

  // Dart reads no_input_device only from resume(). A start without input is a start failure.
  func testAStartWithNoInputIsAStartFailure() {
    h.platform.prepareEngine = { $0.startError = RecorderError.noInputDevice }

    let assertStartFailed = { (error: Error) in
      guard case RecorderError.error(_, let details) = error else { return XCTFail("Got \(error)") }
      XCTAssertEqual(details, "No audio input is available.")
    }
    XCTAssertThrowsError(try h.startRecording(), "file") { assertStartFailed($0) }
    XCTAssertThrowsError(try h.run { try h.controller.startStream(config: makeConfig(encoder: "pcm16bits")) }, "stream") {
      assertStartFailed($0)
    }
  }

  func testStartWhileRecordingEndsTheTakeAndStartsTheNext() throws {
    try h.startRecording()
    try h.startRecording()

    h.run {
      XCTAssertEqual(h.platform.engines.count, 2)
      XCTAssertEqual(h.platform.engines[0].stopDeleteFlags, [false])
      XCTAssertEqual(h.platform.fakeEnvironment.releaseCount, 1)
      XCTAssertEqual(h.platform.fakeEnvironment.prepareCount, 2)
      XCTAssertEqual(h.sink.states, [.record, .stop, .record])
    }
  }

  func testStartStreamRejectsAnEncoderItCannotStream() {
    XCTAssertThrowsError(try h.run { try h.controller.startStream(config: makeConfig(encoder: "wav")) })

    h.run { XCTAssertEqual(h.platform.streamEngineCount, 0) }
  }

  // MARK: - Negotiated config

  func testARenegotiatedConfigIsReportedAndBecomesTheActiveOne() throws {
    let asked = makeConfig(sampleRate: 44100, numChannels: 2)
    h.platform.prepareEngine = {
      $0.effectiveConfig = asked.negotiated(sampleRate: 48000, bitRate: 96000, numChannels: 1)
    }

    try h.startRecording(asked)

    h.run {
      XCTAssertEqual(h.sink.configs.count, 1)
      XCTAssertEqual(h.sink.configs.first?.sampleRate, 48000)
      XCTAssertEqual(h.sink.configs.first?.numChannels, 1)
    }
  }

  func testAnUnchangedConfigIsNotReported() throws {
    try h.startRecording()

    h.run { XCTAssertEqual(h.sink.configs.count, 0) }
  }

  // MARK: - A device that is gone

  func testAMissingDeviceRecordsFromTheDefaultAndIsReported() throws {
    h.platform.fakeDevices.missingIds = [usbMic.id]

    try h.startRecording(makeConfig(device: usbMic))

    h.run {
      XCTAssertNil(h.platform.lastEngine?.config.device)
      XCTAssertEqual(h.sink.configs.count, 1)
      XCTAssertNil(h.sink.configs.first?.device)
      XCTAssertEqual(h.sink.states, [.record])
    }
  }

  // Same rule for a stream. The engine gets the default, and Dart hears it.
  func testAMissingDeviceIsReportedForAStreamToo() throws {
    h.platform.fakeDevices.missingIds = [usbMic.id]

    try h.run {
      try h.controller.startStream(config: makeConfig(encoder: "pcm16bits", device: usbMic))
    }

    h.run {
      XCTAssertNil(h.platform.lastEngine?.config.device)
      XCTAssertNil(h.sink.configs.first?.device)
    }
  }

  func testAPresentDeviceIsKeptAndNotReported() throws {
    try h.startRecording(makeConfig(device: usbMic))

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.config.device?.id, "usb-mic")
      XCTAssertEqual(h.sink.configs.count, 0)
    }
  }

  // MARK: - Pause and resume

  func testAUserPauseReportsPause() throws {
    try h.startRecording()
    h.run { h.controller.pause() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.pauseCount, 1)
      XCTAssertEqual(h.sink.states, [.record, .pause])
      XCTAssertTrue(h.controller.isPaused)
    }
  }

  func testAUserResumeReportsRecord() throws {
    try h.startRecording()
    h.run { h.controller.pause() }
    try h.run { try h.controller.resume() }

    h.run {
      // An interruption may have come during the pause, so the controller takes the audio state back.
      XCTAssertEqual(h.platform.fakeEnvironment.activateCount, 1)
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 1)
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  func testAUserResumeWithoutTheAudioStateStaysPaused() throws {
    try h.startRecording()
    h.run { h.controller.pause() }
    h.platform.fakeEnvironment.activateError = TestError.boom

    XCTAssertThrowsError(try h.run { try h.controller.resume() })

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 0)
      XCTAssertEqual(h.sink.states, [.record, .pause])
      XCTAssertTrue(h.controller.isPaused)
    }
  }

  func testAFailedEngineResumeStaysPaused() throws {
    try h.startRecording()
    h.run { h.controller.pause() }
    h.platform.lastEngine?.resumeError = TestError.boom

    XCTAssertThrowsError(try h.run { try h.controller.resume() })

    h.run {
      XCTAssertEqual(h.sink.states, [.record, .pause])
      XCTAssertTrue(h.controller.isPaused)
    }
  }

  func testPauseAndResumeOutsideTheirStateNeverReachTheEngine() throws {
    try h.run { try h.controller.resume() }
    try h.startRecording()
    try h.run { try h.controller.resume() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 0)
      XCTAssertEqual(h.sink.states, [.record])
    }

    h.run { h.controller.pause() }
    h.run { h.controller.pause() }

    h.run { XCTAssertEqual(h.platform.lastEngine?.pauseCount, 1) }
  }

  // MARK: - Interruptions

  func testAnInterruptionPausesTheTake() throws {
    try h.startRecording(makeConfig(audioInterruption: .pause))

    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()

    h.run { XCTAssertEqual(h.sink.states, [.record, .pause]) }
  }

  func testAnInterruptionEndResumesWhenTheConfigAsksForIt() throws {
    try h.startRecording(makeConfig(audioInterruption: .pauseResume))

    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()
    h.platform.fakeEnvironment.raise(.interruptionEnded(shouldResume: true))
    h.drain()

    h.run {
      // The interruption took the audio state, so the controller takes it back.
      XCTAssertEqual(h.platform.fakeEnvironment.activateCount, 1)
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  // The refactor fixed this. An interruption end must not undo a user pause.
  func testAnInterruptionEndDoesNotResumeATakeTheUserPaused() throws {
    try h.startRecording(makeConfig(audioInterruption: .pauseResume))

    h.run { h.controller.pause() }
    h.platform.fakeEnvironment.raise(.interruptionEnded(shouldResume: true))
    h.drain()

    h.run {
      XCTAssertEqual(h.platform.fakeEnvironment.activateCount, 0)
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 0)
      XCTAssertEqual(h.sink.states, [.record, .pause])
      XCTAssertTrue(h.controller.isPaused)
    }
  }

  // A user pause on top of an interruption pause also stops the auto resume.
  func testAUserPauseOnTopOfAnInterruptionPauseStaysPaused() throws {
    try h.startRecording(makeConfig(audioInterruption: .pauseResume))

    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()
    h.run { h.controller.pause() }
    h.platform.fakeEnvironment.raise(.interruptionEnded(shouldResume: true))
    h.drain()

    h.run { XCTAssertEqual(h.sink.states, [.record, .pause]) }
  }

  // The take never paused, but the system stopped its capture during the call.
  func testAnInterruptionEndRestartsCaptureWithNone() throws {
    try h.startRecording(makeConfig(audioInterruption: AudioInterruptionMode.none))

    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()
    h.platform.fakeEnvironment.raise(.interruptionEnded(shouldResume: true))
    h.drain()

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.restartCount, 1)
      XCTAssertEqual(h.sink.states, [.record])
    }
  }

  func testEnvironmentEventsBeforeRecordingAreIgnored() {
    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()

    h.run { XCTAssertEqual(h.sink.states, []) }
  }

  func testAFailedReactivationGoesToTheSink() throws {
    try h.startRecording(makeConfig(audioInterruption: .pauseResume))
    h.platform.fakeEnvironment.activateError = TestError.boom

    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()
    h.platform.fakeEnvironment.raise(.interruptionEnded(shouldResume: true))
    h.drain()

    h.run {
      XCTAssertEqual(h.sink.errors.count, 1)
      XCTAssertEqual(h.sink.states, [.record, .pause])
    }
  }

  // MARK: - Input changes

  // The engine reports a change. Then the controller reads what became of the input.
  private func changeTheInput(to state: InputState) {
    h.platform.lastEngine?.inputState = state
    h.platform.lastEngine?.raise(.inputChanged)
    h.drain()
  }

  private func loseTheInput() { changeTheInput(to: .lost) }

  func testAnInputChangeThatKeepsTheInputChangesNothing() throws {
    try h.startRecording()

    changeTheInput(to: .ok)

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.restartCount, 0)
      XCTAssertEqual(h.sink.states, [.record])
    }
  }

  // E.g. a headset was connected: the take goes on, on its own input.
  func testAStoppedInputRestartsCapture() throws {
    try h.startRecording()

    changeTheInput(to: .stopped)

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.restartCount, 1)
      XCTAssertEqual(h.sink.states, [.record])
      XCTAssertEqual(h.sink.errors.count, 0)
    }
  }

  // resume() starts it again.
  func testAStoppedInputWaitsForResumeDuringAPause() throws {
    try h.startRecording()
    h.run { h.controller.pause() }

    changeTheInput(to: .stopped)

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.restartCount, 0)
      XCTAssertEqual(h.sink.states, [.record, .pause])
    }
  }

  // E.g. a call took the input, and its interruption notice is still to come. The take waits.
  func testAFailedRestartPausesTheTake() throws {
    try h.startRecording()
    h.platform.lastEngine?.restartError = TestError.boom

    changeTheInput(to: .stopped)

    h.run {
      XCTAssertEqual(h.sink.states, [.record, .pause])
      XCTAssertEqual(h.sink.errors.count, 0)
      XCTAssertEqual(h.platform.lastEngine?.stopDeleteFlags, [])
    }
  }

  // E.g. macOS: no interruption end would ever come.
  func testAFailedRestartEndsTheTakeWithoutInterruptions() throws {
    h.platform.fakeEnvironment.sendsInterruptions = false
    try h.startRecording()
    h.platform.lastEngine?.restartError = TestError.boom

    changeTheInput(to: .stopped)

    h.run {
      XCTAssertEqual(h.sink.states, [.record, .stop])
      XCTAssertEqual(h.sink.errors.count, 1)
      XCTAssertEqual(h.platform.lastEngine?.stopDeleteFlags, [false])
    }
  }

  // The take must not pause, and nothing may restart it. So it ends, and Dart learns why.
  func testAFailedRestartEndsTheTakeWithNone() throws {
    try h.startRecording(makeConfig(audioInterruption: AudioInterruptionMode.none))
    h.platform.lastEngine?.restartError = TestError.boom

    changeTheInput(to: .stopped)

    h.run {
      XCTAssertEqual(h.sink.states, [.record, .stop])
      XCTAssertEqual(h.sink.errors.count, 1)
      XCTAssertEqual(h.platform.lastEngine?.stopDeleteFlags, [false])
    }
  }

  func testAnInterruptionEndResumesAFailedRestart() throws {
    try h.startRecording(makeConfig(audioInterruption: .pauseResume))
    h.platform.lastEngine?.restartError = TestError.boom
    changeTheInput(to: .stopped)

    h.platform.lastEngine?.restartError = nil
    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()
    h.platform.fakeEnvironment.raise(.interruptionEnded(shouldResume: true))
    h.drain()

    h.run {
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  // The input can go while the restart builds on it. It is a loss like any other.
  func testARestartThatFindsNoInputIsALoss() throws {
    try h.startRecording(makeConfig(audioRouteChange: .pause))
    h.platform.lastEngine?.restartError = RecorderError.noInputDevice

    changeTheInput(to: .stopped)

    h.run {
      XCTAssertEqual(h.sink.states, [.record, .pause])
      XCTAssertEqual(h.sink.errors.count, 0)
    }
  }

  // MARK: - Route change

  func testPauseModePausesTheTakeWhenTheInputIsGone() throws {
    try h.startRecording(makeConfig(device: usbMic, audioRouteChange: .pause))

    loseTheInput()

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.pauseCount, 1)
      XCTAssertEqual(h.platform.lastEngine?.reroutes.count, 0)
      XCTAssertEqual(h.sink.states, [.record, .pause])
      XCTAssertTrue(h.controller.isPaused)
    }
  }

  // Else the take would resume on another device without the app asking.
  func testAnInterruptionEndDoesNotResumeATakePausedByARouteLoss() throws {
    try h.startRecording(makeConfig(audioInterruption: .pauseResume, audioRouteChange: .pause))

    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()
    loseTheInput()
    h.platform.fakeEnvironment.raise(.interruptionEnded(shouldResume: true))
    h.drain()

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 0)
      XCTAssertEqual(h.sink.states, [.record, .pause])
    }
  }

  // The same, when the loss event comes after the interruption end.
  func testAnInterruptionEndDoesNotResumeATakeWhoseInputIsGone() throws {
    try h.startRecording(makeConfig(audioInterruption: .pauseResume, audioRouteChange: .pause))

    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()
    h.platform.lastEngine?.inputState = .lost
    h.platform.fakeEnvironment.raise(.interruptionEnded(shouldResume: true))
    h.drain()

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes.count, 0)
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 0)
      XCTAssertEqual(h.sink.states, [.record, .pause])
      XCTAssertEqual(h.sink.errors.count, 0)
    }
  }

  // The follow mode moves the take, so the interruption end can resume it.
  func testAnInterruptionEndResumesOnTheDefaultInputInFollowMode() throws {
    try h.startRecording(makeConfig(audioInterruption: .pauseResume, audioRouteChange: .follow))

    h.platform.fakeEnvironment.raise(.interrupted)
    h.drain()
    h.platform.lastEngine?.inputState = .lost
    h.platform.fakeEnvironment.raise(.interruptionEnded(shouldResume: true))
    h.drain()

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, [nil])
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  func testAResumeAfterARouteLossGoesBackToTheDeviceWhenItReturned() throws {
    try h.startRecording(makeConfig(device: usbMic, audioRouteChange: .pause))
    loseTheInput()

    try h.run { try h.controller.resume() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, ["usb-mic"])
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 1)
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
      // Still on the device Dart asked for, so nothing to report.
      XCTAssertEqual(h.sink.configs.count, 0)
    }
  }

  // A user pause does not hide the loss: resume() moves capture before it starts.
  func testAUserPauseAfterARouteLossStillMovesCaptureFirst() throws {
    try h.startRecording(makeConfig(device: usbMic, audioRouteChange: .pause))
    loseTheInput()
    h.run { h.controller.pause() }

    try h.run { try h.controller.resume() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, ["usb-mic"])
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 1)
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  // Like android and web: the device Dart asked for, even when it was missing at start.
  func testAResumeGoesToTheAskedDeviceEvenIfTheTakeStartedWithoutIt() throws {
    h.platform.fakeDevices.missingIds = [usbMic.id]
    try h.startRecording(makeConfig(device: usbMic, audioRouteChange: .pause))
    h.platform.fakeDevices.missingIds = []
    loseTheInput()

    try h.run { try h.controller.resume() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, ["usb-mic"])
      // First the fallback to the default input, then the move back to the asked device.
      XCTAssertEqual(h.sink.configs.map { $0.device?.id }, [nil, "usb-mic"])
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  func testAResumeAfterARouteLossMovesToTheDefaultInputAndReportsIt() throws {
    try h.startRecording(makeConfig(device: usbMic, audioRouteChange: .pause))
    loseTheInput()
    h.platform.fakeDevices.missingIds = [usbMic.id]

    try h.run { try h.controller.resume() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, [nil])
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
      XCTAssertEqual(h.sink.configs.count, 1)
      XCTAssertNil(h.sink.configs.first?.device)
    }
  }

  func testAResumeWithNoInputThrowsStaysPausedAndCanTryAgain() throws {
    try h.startRecording(makeConfig(audioRouteChange: .pause))
    loseTheInput()
    h.platform.lastEngine?.rerouteError = RecorderError.noInputDevice

    XCTAssertThrowsError(try h.run { try h.controller.resume() }) { assertNoInputDevice($0) }
    h.run {
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 0)
      XCTAssertEqual(h.sink.states, [.record, .pause])
    }

    // A device came back.
    h.platform.lastEngine?.rerouteError = nil
    try h.run { try h.controller.resume() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, [nil, nil])
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  // The device went during a user pause, and its event did not come yet.
  func testAResumeFindsALossTheEventDidNotReportYet() throws {
    try h.startRecording(makeConfig(device: usbMic, audioRouteChange: .pause))
    h.run { h.controller.pause() }
    h.platform.lastEngine?.inputState = .lost
    h.platform.fakeDevices.missingIds = [usbMic.id]

    try h.run { try h.controller.resume() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, [nil])
      XCTAssertNil(h.sink.configs.last?.device)
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  func testAResumeThatFindsALossInStopModeEndsTheTake() throws {
    try h.startRecording(makeConfig(audioRouteChange: .stop))
    h.run { h.controller.pause() }
    h.platform.lastEngine?.inputState = .lost

    try h.run { try h.controller.resume() }

    h.run {
      XCTAssertEqual(h.sink.states, [.record, .pause, .stop])
      XCTAssertEqual(h.platform.lastEngine?.stopDeleteFlags, [false])
    }
  }

  // No input left is expected. Any other failure, Dart must hear.
  func testFollowModeReportsAFailureThatIsNotAMissingInput() throws {
    try h.startRecording(makeConfig(audioRouteChange: .follow))
    h.platform.lastEngine?.rerouteError = TestError.boom

    loseTheInput()

    h.run {
      XCTAssertEqual(h.sink.states, [.record, .pause])
      XCTAssertEqual(h.sink.errors.count, 1)
    }
  }

  func testASecondLossWhilePausedForOneChangesNothing() throws {
    try h.startRecording(makeConfig(audioRouteChange: .follow))
    h.platform.lastEngine?.rerouteError = RecorderError.noInputDevice
    loseTheInput()
    loseTheInput()

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes.count, 1)
      XCTAssertEqual(h.sink.states, [.record, .pause])
    }
  }

  func testFollowModeMovesToTheDefaultInputAndReportsIt() throws {
    try h.startRecording(makeConfig(device: usbMic, audioRouteChange: .follow))

    loseTheInput()

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, [nil])
      // Dart never sees a pause.
      XCTAssertEqual(h.sink.states, [.record])
      XCTAssertEqual(h.sink.configs.count, 1)
      XCTAssertNil(h.sink.configs.first?.device)
    }
  }

  func testFollowModeOnTheDefaultInputHasNothingToReport() throws {
    try h.startRecording(makeConfig(audioRouteChange: .follow))

    loseTheInput()

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, [nil])
      XCTAssertEqual(h.sink.configs.count, 0)
    }
  }

  func testFollowModePausesWhenNoInputIsLeft() throws {
    try h.startRecording(makeConfig(audioRouteChange: .follow))
    h.platform.lastEngine?.rerouteError = RecorderError.noInputDevice

    loseTheInput()
    h.run { XCTAssertEqual(h.sink.states, [.record, .pause]) }

    // A device came back. resume() moves capture again.
    h.platform.lastEngine?.rerouteError = nil
    try h.run { try h.controller.resume() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, [nil, nil])
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  func testFollowModeKeepsAUserPauseAndResumesOnTheNewInput() throws {
    try h.startRecording(makeConfig(device: usbMic, audioRouteChange: .follow))
    h.run { h.controller.pause() }

    loseTheInput()

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.reroutes, [nil])
      XCTAssertEqual(h.platform.lastEngine?.resumeCount, 0)
      XCTAssertEqual(h.sink.states, [.record, .pause])
    }

    try h.run { try h.controller.resume() }

    h.run {
      // Capture moved already. The resume only starts it.
      XCTAssertEqual(h.platform.lastEngine?.reroutes, [nil])
      XCTAssertEqual(h.sink.states, [.record, .pause, .record])
    }
  }

  func testStopModeEndsTheTakeAndKeepsTheFile() throws {
    try h.startRecording(makeConfig(audioRouteChange: .stop))

    loseTheInput()

    h.run {
      XCTAssertEqual(h.sink.states, [.record, .stop])
      XCTAssertEqual(h.platform.lastEngine?.stopDeleteFlags, [false])
      XCTAssertEqual(h.platform.fakeEnvironment.releaseCount, 1)
      // Stopping is what the app asked for, so it is no error.
      XCTAssertEqual(h.sink.errors.count, 0)
    }
  }

  // MARK: - Stop, cancel, dispose

  func testStopReleasesEverythingAndAnswersWithThePath() throws {
    try h.startRecording()

    let path = h.run { h.controller.stop() }

    XCTAssertEqual(path, "/tmp/take.m4a")
    h.run {
      XCTAssertEqual(h.platform.lastEngine?.stopDeleteFlags, [false])
      XCTAssertEqual(h.platform.fakeEnvironment.releaseCount, 1)
      XCTAssertEqual(h.sink.states, [.record, .stop])
      XCTAssertFalse(h.controller.isRecording)
    }
  }

  func testCancelAsksTheEngineToDelete() throws {
    try h.startRecording()

    h.run { h.controller.cancel() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.stopDeleteFlags, [true])
      XCTAssertEqual(h.platform.fakeEnvironment.releaseCount, 1)
      XCTAssertEqual(h.sink.states, [.record, .stop])
    }
  }

  func testStopWhileIdleDoesNothing() {
    let path = h.run { h.controller.stop() }

    XCTAssertNil(path)
    h.run {
      XCTAssertEqual(h.platform.fakeEnvironment.releaseCount, 0)
      XCTAssertEqual(h.sink.states, [])
    }
  }

  func testDisposeStopsTheEngineAndReleasesTheEnvironment() throws {
    try h.startRecording()

    h.run { h.controller.dispose() }

    h.run {
      XCTAssertEqual(h.platform.lastEngine?.stopDeleteFlags, [false])
      XCTAssertEqual(h.platform.fakeEnvironment.releaseCount, 1)
      XCTAssertEqual(h.sink.states, [.record, .stop])
    }
  }

  // MARK: - Engine failures

  func testASpontaneousFailureEndsTheTakeAndReportsTheError() throws {
    try h.startRecording()

    h.platform.lastEngine?.raise(.terminated(TestError.boom))
    h.drain()

    h.run {
      XCTAssertEqual(h.platform.fakeEnvironment.releaseCount, 1)
      XCTAssertEqual(h.sink.states, [.record, .stop])
      XCTAssertEqual(h.sink.errors.count, 1)
      XCTAssertFalse(h.controller.isRecording)
    }
  }

  // The take id is what makes an old engine's late report harmless.
  func testAFailureFromASupersededEngineIsIgnored() throws {
    try h.startRecording()
    let first = h.platform.lastEngine
    try h.startRecording()

    first?.raise(.terminated(TestError.boom))
    h.drain()

    h.run {
      XCTAssertEqual(h.sink.errors.count, 0)
      XCTAssertEqual(h.sink.states, [.record, .stop, .record])
      XCTAssertTrue(h.controller.isRecording)
    }
  }

  func testChunksFromASupersededEngineAreIgnored() throws {
    try h.startRecording()
    let first = h.platform.lastEngine
    try h.startRecording()

    first?.raise(.chunk(Data([1, 2, 3])))
    h.platform.lastEngine?.raise(.chunk(Data([4, 5])))
    h.drain()

    h.run {
      XCTAssertEqual(h.sink.chunks, [Data([4, 5])])
    }
  }

  // MARK: - Amplitude

  func testAmplitudeIsTheFloorWhileIdle() {
    let amplitude = h.run { h.controller.amplitude() }

    XCTAssertEqual(amplitude.current, silenceDb)
    XCTAssertEqual(amplitude.max, silenceDb)
  }

  func testAmplitudeReadsTheEngineAndKeepsThePeak() throws {
    h.platform.prepareEngine = { $0.amplitudeValue = -20 }
    try h.startRecording()

    var amplitude = h.run { h.controller.amplitude() }
    XCTAssertEqual(amplitude.current, -20)
    XCTAssertEqual(amplitude.max, -20)

    h.run { h.platform.lastEngine?.amplitudeValue = -40 }
    amplitude = h.run { h.controller.amplitude() }

    XCTAssertEqual(amplitude.current, -40)
    XCTAssertEqual(amplitude.max, -20)
  }

  func testThePeakResetsBetweenTakes() throws {
    h.platform.prepareEngine = { $0.amplitudeValue = -10 }
    try h.startRecording()
    _ = h.run { h.controller.amplitude() }

    h.platform.prepareEngine = { $0.amplitudeValue = -50 }
    try h.startRecording()
    let amplitude = h.run { h.controller.amplitude() }

    XCTAssertEqual(amplitude.max, -50)
  }
}
