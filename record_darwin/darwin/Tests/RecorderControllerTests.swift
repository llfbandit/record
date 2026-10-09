import XCTest

@testable import record_darwin

// Mirrors android's RecorderControllerTest.
final class RecorderControllerTests: XCTestCase {
  private var h = ControllerHarness()

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
    h.platform.fakeDevices.missingIds = ["usb-mic"]

    try h.startRecording(makeConfig(device: Device(id: "usb-mic", label: "USB mic")))

    h.run {
      XCTAssertNil(h.platform.lastEngine?.config.device)
      XCTAssertEqual(h.sink.configs.count, 1)
      XCTAssertNil(h.sink.configs.first?.device)
      XCTAssertEqual(h.sink.states, [.record])
    }
  }

  // Same rule for a stream. The engine gets the default, and Dart hears it.
  func testAMissingDeviceIsReportedForAStreamToo() throws {
    h.platform.fakeDevices.missingIds = ["usb-mic"]

    try h.run {
      try h.controller.startStream(config: makeConfig(encoder: "pcm16bits", device: Device(id: "usb-mic", label: "USB mic")))
    }

    h.run {
      XCTAssertNil(h.platform.lastEngine?.config.device)
      XCTAssertNil(h.sink.configs.first?.device)
    }
  }

  func testAPresentDeviceIsKeptAndNotReported() throws {
    try h.startRecording(makeConfig(device: Device(id: "usb-mic", label: "USB mic")))

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
