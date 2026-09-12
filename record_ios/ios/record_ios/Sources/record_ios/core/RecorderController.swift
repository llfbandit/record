import Foundation

// Where a recorder's output goes.
protocol RecorderSink: AnyObject {
  func onState(_ state: RecordState)
  func onChunk(_ data: Data)
  func onConfigChanged(_ config: RecordConfig)
  func onError(_ error: Error)
}

struct Amplitude {
  let current: Float
  let max: Float
}

// Drives one recorder. Everything runs on the queue given at init, so we use no lock here.
final class RecorderController {
  private final class Session {
    // Tells the events of the running take from the events of an old take.
    let id: Int
    let engine: CaptureEngine
    var config: RecordConfig
    // Stays .stop until the engine has started.
    var state: RecordState = .stop
    var maxAmplitude = silenceDb
    // The policy paused it, not the user. Only this one can resume by itself.
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
    m_platform.environment.onEvent = { [weak self] event in
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
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "\(config.encoder) not supported."
      )
    }

    try beginTake(config) { takeId in
      self.m_platform.makeFileEngine(
        config: config, path: path, onEvent: self.handler(forTake: takeId))
    }
  }

  func startStream(config: RecordConfig) throws {
    guard config.encoder == AudioEncoder.pcm16bits.rawValue
            || config.encoder == AudioEncoder.aacLc.rawValue else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "\(config.encoder) not supported in streaming mode."
      )
    }

    try beginTake(config) { takeId in
      self.m_platform.makeStreamEngine(config: config, onEvent: self.handler(forTake: takeId))
    }
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

    guard let session = m_session, session.state == .record, session.engine.pause() else { return }

    // The user asked for it. The end of an interruption must not undo it.
    session.pausedByPolicy = false
    moveTo(session, .pause)
  }

  func resume() throws {
    assertOnQueue()

    guard let session = m_session, session.state == .pause else { return }
    guard try session.engine.resume() else { return }

    session.pausedByPolicy = false
    moveTo(session, .record)
  }

  // Current and max input level. Returns the floor when we capture nothing.
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
    assertOnQueue()

    end(delete: false)
  }

  // MARK: - Private

  private func beginTake(_ config: RecordConfig, _ makeEngine: (Int) -> CaptureEngine) throws {
    assertOnQueue()

    // End the running take first. start() also means "start the next take".
    end(delete: false)

    try m_platform.environment.prepare(config)

    m_lastTakeId += 1
    let engine = makeEngine(m_lastTakeId)
    let session = Session(id: m_lastTakeId, engine: engine, config: config)
    m_session = session

    do {
      let effective = try engine.start()
      session.config = effective

      if effective.isModified(from: config) { m_sink.onConfigChanged(effective) }

      moveTo(session, .record)
    } catch {
      // Nothing started, so we must leave nothing behind.
      m_session = nil
      engine.stop(delete: true)
      m_platform.environment.release()
      throw error
    }
  }

  // Set at init. The take id is copied, so we drop an event that comes too late.
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
      if let error { m_sink.onError(error) }
    }
  }

  private func onEnvironmentEvent(_ event: EnvironmentEvent) {
    guard let session = m_session else { return }

    switch EnvironmentPolicy.react(config: session.config, event: event) {
    case nil:
      break

    case .pause:
      guard session.state == .record, session.engine.pause() else { return }
      session.pausedByPolicy = true
      moveTo(session, .pause)

    case .resume:
      // A take the user paused stays paused.
      guard session.pausedByPolicy else { return }
      do {
        // The interruption stole the audio state. Take it back first.
        try m_platform.environment.activate()
        try resume()
      } catch {
        m_sink.onError(error)
      }
    }
  }

  // Sending the same state twice would look like a second take on the Dart side.
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
