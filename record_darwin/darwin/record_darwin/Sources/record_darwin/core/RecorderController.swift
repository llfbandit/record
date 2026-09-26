import Foundation

// Where a recorder's output goes.
protocol RecorderSink: AnyObject {
  func onState(_ state: RecordState)
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
    // Paused by the policy, not the user. Only this one auto-resumes.
    var pausedByPolicy = false

    init(id: Int, engine: CaptureEngine, config: RecordConfig) {
      self.id = id
      self.engine = engine
      self.config = config
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

    // The user owns the pause now. An interruption end must not undo it.
    session.pausedByPolicy = false

    guard session.state == .record else { return }

    session.engine.pause()
    moveTo(session, .pause)
  }

  func resume() throws {
    assertOnQueue()

    guard let session = m_session, session.state == .pause else { return }
    // An interruption during the pause takes the audio state. Take it back first.
    try m_platform.environment.activate()
    try session.engine.resume()

    session.pausedByPolicy = false
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
    var config = asked
    if let device = asked.device, !m_platform.devices.isAvailable(device) {
      config = asked.withDefaultDevice()
    }

    m_lastTakeId += 1
    let engine = m_platform.makeEngine(config: config, target: target, onEvent: handler(forTake: m_lastTakeId))
    let session = Session(id: m_lastTakeId, engine: engine, config: config)
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
  private func end(delete: Bool) -> String? {
    guard let session = m_session else { return nil }

    // Drop it now, so the next take cannot mix with this one.
    m_session = nil

    let path = session.engine.stop(delete: delete)
    m_platform.environment.release()
    moveTo(session, .stop)

    return path
  }

  private func onCaptureEvent(_ event: CaptureEvent, take: Int) {
    // Ignore the events of a take that is not the current one.
    guard let session = m_session, session.id == take else { return }

    switch event {
    case .chunk(let data):
      m_sink.onChunk(data)

    case .terminated(let error):
      end(delete: false)
      m_sink.onError(error)
    }
  }

  private func onEnvironmentEvent(_ event: EnvironmentEvent) {
    guard let session = m_session else { return }

    switch EnvironmentPolicy.react(config: session.config, event: event) {
    case nil:
      break

    case .pause:
      guard session.state == .record else { return }
      session.engine.pause()
      session.pausedByPolicy = true
      moveTo(session, .pause)

    case .resume:
      // A take the user paused stays paused.
      guard session.pausedByPolicy else { return }
      do {
        try resume()
      } catch {
        m_sink.onError(error)
      }
    }
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
