import Foundation

// Where a recorder's output goes.
protocol RecorderSink: AnyObject {
  // Pause and record. A take ends with onStopped.
  func onState(_ state: RecordState)
  func onStopped(_ stop: RecordStop)
  func onChunk(_ data: Data)
  func onConfigChanged(_ config: RecordConfig)
  func onError(_ error: Error)
}

// Drives one recorder, always on the queue given at init.
final class RecorderController {
  private final class Session {
    // Tells the running take from an old one.
    let id: Int
    let engine: CaptureEngine
    var config: RecordConfig
    // Stays .stop until the engine has started.
    var state: RecordState = .stop
    var maxAmplitude = silenceDb
    // Nil while the take records.
    var pauseReason: PauseReason?
    // What Dart asked for. resume() goes back to it when it returns, even if the take never used it.
    let requestedDevice: Device?

    init(id: Int, engine: CaptureEngine, config: RecordConfig, requestedDevice: Device?) {
      self.id = id
      self.engine = engine
      self.config = config
      self.requestedDevice = requestedDevice
    }
  }

  private let m_queue: DispatchQueue
  private let m_platform: RecorderPlatform
  private let m_sink: RecorderSink
  private var m_session: Session?
  private var m_lastTakeId = 0

  init(queue: DispatchQueue, platform: RecorderPlatform, sink: RecorderSink) {
    m_queue = queue
    m_platform = platform
    m_sink = sink

    // Set once. release() is what stops the reports.
    m_platform.environment.bind { [weak self] event in
      self?.m_queue.async { self?.onEnvironmentEvent(event) }
    }
  }

  var isRecording: Bool {
    assertOnQueue()
    return m_session.map { $0.state != .stop } ?? false
  }

  var isPaused: Bool {
    assertOnQueue()
    return m_session?.state == .pause
  }

  func start(config: RecordConfig, path: String) throws {
    guard m_platform.supportedEncoders.contains(config.encoder) else {
      throw RecorderError.startFailed("\(config.encoder) not supported.")
    }

    try beginTake(config, target: .file(path: path))
  }

  func startStream(config: RecordConfig) throws {
    guard AudioStreamProcessor.encoders.contains(config.encoder) else {
      throw RecorderError.startFailed("\(config.encoder) not supported in streaming mode.")
    }

    try beginTake(config, target: .stream)
  }

  @discardableResult
  func stop() -> String? {
    assertOnQueue()
    return end(delete: false)
  }

  func cancel() {
    assertOnQueue()
    end(delete: true)
  }

  func pause() {
    assertOnQueue()

    guard let session = m_session else { return }

    // The user owns the pause now, so an interruption end cannot undo it.
    pause(session, for: .user)
  }

  func resume() throws {
    assertOnQueue()

    guard let session = m_session, session.state == .pause else { return }
    // An interruption during the pause takes the audio state. Take it back first.
    try m_platform.environment.activate()

    reactIfInputLost(session)
    // The stop mode ended the take.
    guard m_session === session else { return }

    try resumeCapture(session)
    session.pauseReason = nil
    moveTo(session, .record)
  }

  // Current and max input level.
  func amplitude() -> Amplitude {
    assertOnQueue()

    guard let session = m_session, session.state != .stop else {
      return Amplitude(current: silenceDb, max: silenceDb)
    }

    let current = session.engine.amplitude
    session.maxAmplitude = max(session.maxAmplitude, current)

    let clamped = min(0, max(current, silenceDb))
    let peak = min(0, max(session.maxAmplitude, silenceDb))

    return Amplitude(current: clamped, max: peak)
  }

  func dispose() {
    stop()
  }

  // MARK: - Private

  private func beginTake(
    _ asked: RecordConfig,
    target: CaptureTarget
  ) throws {
    assertOnQueue()

    // End the running take first. start() also means "next take".
    end(delete: false)

    try m_platform.environment.prepare(asked)

    // The device is gone, so we record from the default input. Dart is told below.
    let config = asked.withDevice(m_platform.devices.available(asked.device))

    m_lastTakeId += 1
    let engine = m_platform.makeEngine(config: config, target: target, onEvent: handler(forTake: m_lastTakeId))
    let session = Session(id: m_lastTakeId, engine: engine, config: config, requestedDevice: asked.device)
    m_session = session

    do {
      let effective = try engine.start()
      session.config = effective

      if effective.isModified(from: asked) { m_sink.onConfigChanged(effective) }

      moveTo(session, .record)
    } catch {
      // Nothing started, so we must leave nothing behind.
      m_session = nil
      engine.stop(delete: true)
      m_platform.environment.release()
      // Dart reads noInputDevice only from resume(). A start without input is a start failure.
      if case RecorderError.noInputDevice = error { throw RecorderError.startFailed("No audio input is available.") }
      throw error
    }
  }

  // The take id is copied, so a late event is dropped.
  private func handler(forTake takeId: Int) -> (CaptureEvent) -> Void {
    { [weak self] event in
      guard let self else { return }
      // Engines call us from their own threads.
      self.m_queue.async { self.onCaptureEvent(event, take: takeId) }
    }
  }

  @discardableResult
  private func end(delete: Bool, reason: StopReason = .stop, error: Error? = nil) -> String? {
    guard let session = m_session else { return nil }

    // Drop it now, so the next take cannot mix with this one.
    m_session = nil

    let path = session.engine.stop(delete: delete)
    m_platform.environment.release()

    if session.state != .stop {
      session.state = .stop
      m_sink.onStopped(RecordStop(reason, path: delete ? nil : path, error: error))
    }

    return path
  }

  private func onCaptureEvent(_ event: CaptureEvent, take: Int) {
    // Ignore the events of a take that is not the current one.
    guard let session = m_session, session.id == take else { return }

    switch event {
    case .chunk(let data):
      m_sink.onChunk(data)

    case .inputChanged:
      switch session.engine.inputState {
      case .ok: break
      case .stopped: react(to: .inputStopped, session)
      case .lost: react(to: .inputLost, session)
      }

    case .terminated(let error):
      fail(error)
    }
  }

  private func onEnvironmentEvent(_ event: EnvironmentEvent) {
    guard let session = m_session else { return }
    react(to: .environment(event), session)
  }

  // The error made the event. A take it ends reports it.
  private func react(to event: TakeEvent, _ session: Session, error: Error? = nil) {
    guard let action = TakePolicy.react(to: event, config: session.config, pausedFor: session.pauseReason) else { return }

    switch action {
    case .pause(let reason):
      pause(session, for: reason)

    case .resume:
      // The input may be gone. Its mode comes first: the pause mode keeps the take paused.
      reactIfInputLost(session)
      guard m_session === session, session.pauseReason == .interruption else { return }

      do {
        try resume()
      } catch {
        m_sink.onError(error)
      }

    case .restart:
      do {
        try session.engine.restart()
      } catch RecorderError.noInputDevice {
        // The input went while the restart built on it.
        react(to: .inputLost, session)
      } catch {
        react(to: .restartFailed(sendsInterruptions: m_platform.environment.sendsInterruptions), session, error: error)
      }

    case .moveToDefault:
      do {
        try move(session, to: nil)
      } catch {
        // resume() tries again. No input left is no error for Dart.
        pause(session, for: .inputLost)
        if case RecorderError.noInputDevice = error { return }
        m_sink.onError(error)
      }

    case .end(let reason):
      // Only an error stop says what failed. The state stream gets the error anyway.
      end(delete: false, reason: reason, error: reason == .error ? error : nil)
      if let error { m_sink.onError(error) }
    }
  }

  // The device can go during a pause, and its event still waits in the queue.
  private func reactIfInputLost(_ session: Session) {
    guard session.engine.inputState == .lost else { return }
    react(to: .inputLost, session)
  }

  // Ends the take, keeps the file, and tells Dart why.
  private func fail(_ error: Error) {
    end(delete: false, reason: .error, error: error)
    m_sink.onError(error)
  }

  private func pause(_ session: Session, for reason: PauseReason) {
    // A lost input stays the reason until resume() moves capture.
    if session.pauseReason != .inputLost { session.pauseReason = reason }

    guard session.state == .record else { return }
    session.engine.pause()
    moveTo(session, .pause)
  }

  // After a loss, capture moves first: to the chosen device if it came back, else the default input.
  private func resumeCapture(_ session: Session) throws {
    if session.pauseReason == .inputLost {
      try move(session, to: m_platform.devices.available(session.requestedDevice))
      // Capture moved. If the start below fails, only the user resumes.
      session.pauseReason = .user
    }
    try session.engine.resume()
  }

  // Moves capture to the device, and tells Dart when it changed. Nil is the default input.
  private func move(_ session: Session, to device: Device?) throws {
    try session.engine.reroute(to: device)

    let moved = session.config.withDevice(device)
    guard moved.isModified(from: session.config) else { return }
    session.config = moved
    m_sink.onConfigChanged(moved)
  }

  // The same state twice would look like a second take in Dart.
  private func moveTo(_ session: Session, _ state: RecordState) {
    guard session.state != state else { return }

    session.state = state
    m_sink.onState(state)
  }

  // Everything runs on one queue. That is why we use no lock.
  private func assertOnQueue() {
    #if DEBUG
    dispatchPrecondition(condition: .onQueue(m_queue))
    #endif
  }
}
