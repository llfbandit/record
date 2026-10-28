import AVFoundation

// Where a take sends its audio.
enum CaptureTarget {
  case stream
  case file(path: String)
}

// Runs one take: an output fed by a CaptureInput. File and stream takes use it, on iOS and macOS.
// The tap runs on its own thread, so we lock.
// A take stays on the input it started with. When the system stops or moves capture, restart() puts it
// back there. When the input is gone, the controller may reroute() it to another one.
// Either way, a new input feeds the same output, so the take goes on in the same file.
final class AudioEngineCapture: CaptureEngine {
  private let m_config: RecordConfig
  private let m_target: CaptureTarget
  private let m_input: InputTracker
  private let m_openInput: OpenInput
  private let m_onEvent: (CaptureEvent) -> Void
  private let m_lock = NSLock()

  // A new one at each input move. Nil after a move that failed.
  private var m_engine: CaptureInput?
  // The format we feed the output. The tap reads it, under the lock.
  private var m_feedFormat: AVAudioFormat?

  private var m_output: CaptureOutput?
  private var m_isPaused = false
  private var m_hasFailed = false
  private var m_amplitude = silenceDb

  init(
    config: RecordConfig,
    target: CaptureTarget,
    input: InputTracker,
    openInput: @escaping OpenInput,
    onEvent: @escaping (CaptureEvent) -> Void
  ) {
    m_config = config
    m_target = target
    m_input = input
    m_openInput = openInput
    m_onEvent = onEvent
  }

  func start() throws -> RecordConfig {
    if case .file(let path) = m_target { try RecordFile.delete(at: path) }

    do {
      let engine = try open(on: m_config.device?.id)
      let negotiated = try FormatPolicy.negotiate(for: m_config, input: engine.format)
      let output = try makeOutput(settings: negotiated.settings, config: negotiated.effective, srcFormat: engine.format)
      m_lock.withLock {
        m_output = output
        m_feedFormat = engine.format
      }

      try engine.start()
      return negotiated.effective
    } catch {
      // Leave nothing behind: no engine, no file.
      stop(delete: true)
      throw error
    }
  }

  func pause() {
    // The input sends the frames it holds when it pauses. They still go to the output.
    m_engine?.pause()
    m_lock.withLock { m_isPaused = true }
  }

  // Starts again after a pause. It writes to the same output, so nothing is lost.
  func resume() throws {
    guard m_lock.withLock({ m_output != nil }) else { return }

    try restart()
    m_lock.withLock { m_isPaused = false }
  }

  var inputState: InputState {
    // First: a macOS engine can run on after its device is gone.
    guard m_input.isAvailable else { return .lost }
    guard let engine = m_engine, engine.isRunning, engine.isCurrent else { return .stopped }
    return .ok
  }

  // Makes a new engine first when the input moved or changed its format.
  func restart() throws {
    do {
      // Else the engine could start again on another input, and the loss would never be reported.
      guard m_input.isAvailable else { throw RecorderError.noInputDevice }

      if m_engine?.isCurrent != true { try reopen(on: m_input.uid) }
      try m_engine?.start()
    } catch {
      // The device can go while we build on it.
      guard m_input.isAvailable else { throw RecorderError.noInputDevice }
      // The input is there, but gives no format for a moment. It is not gone.
      if case RecorderError.noInputDevice = error { throw RecorderError.startFailed("The audio input gives no format.") }
      throw error
    }
  }

  func reroute(to device: Device?) throws {
    try reopen(on: device?.id)

    // A paused take stays paused.
    if !m_lock.withLock({ m_isPaused }) { try m_engine?.start() }
  }

  @discardableResult
  func stop(delete: Bool) -> String? {
    closeEngine()
    m_input.release()

    let output = m_lock.withLock { () -> CaptureOutput? in
      let output = m_output
      m_output = nil
      return output
    }

    // Closing writes the end of the file.
    return output?.close(delete: delete)
  }

  var amplitude: Float {
    m_lock.withLock { m_output == nil ? silenceDb : m_amplitude }
  }

  // MARK: - Private

  // Replaces the engine with a new one on the input with this UID. Nil is the default input. It is not started.
  private func open(on deviceId: String?) throws -> CaptureInput {
    // One engine at a time: the old one must free the input first.
    closeEngine()

    let uid = try m_input.bind(deviceId, channels: m_config.numChannels)
    let engine = try m_openInput(
      uid,
      { [weak self] in self?.handleTap($0) },
      { [m_onEvent] in m_onEvent(.inputChanged) }
    )
    m_engine = engine
    return engine
  }

  // Moves the output to a new engine on the input with this UID. The engine is not started.
  private func reopen(on deviceId: String?) throws {
    let engine = try open(on: deviceId)
    // The converter holds a few frames, so we keep it when we can.
    guard engine.format != m_lock.withLock({ m_feedFormat }) else { return }

    do {
      try m_lock.withLock {
        try m_output?.setInputFormat(engine.format)
        m_feedFormat = engine.format
      }
    } catch {
      closeEngine()
      throw error
    }
  }

  private func closeEngine() {
    m_engine?.close()
    m_engine = nil
  }

  private func makeOutput(settings: [String: Any], config: RecordConfig, srcFormat: AVAudioFormat) throws -> CaptureOutput {
    switch m_target {
    case .stream:
      let processor = try AudioStreamProcessor(config: config, srcFormat: srcFormat)
      return StreamOutput(processor: processor) { [m_onEvent] in m_onEvent(.chunk($0)) }

    case .file(let path):
      // pcm16bits has no container. We write the raw stream bytes.
      guard let fileType = FormatPolicy.fileType(for: config.encoder) else {
        let processor = try AudioStreamProcessor(config: config, srcFormat: srcFormat)
        return try RawFileOutput(path: path, processor: processor)
      }
      return try AudioFileOutput(path: path, settings: settings, fileType: fileType, srcFormat: srcFormat)
    }
  }

  // Runs under the lock, so stop() cannot close the output during a write.
  private func handleTap(_ buffer: AVAudioPCMBuffer) {
    let failure = m_lock.withLock { () -> Error? in
      guard !m_isPaused, !m_hasFailed, let output = m_output else { return nil }
      // After a move, the old input can still send a buffer. We drop it.
      guard let feed = m_feedFormat, buffer.format.hasSameLayout(as: feed) else { return nil }

      m_amplitude = Self.peakDb(buffer)
      do {
        try output.write(buffer)
        return nil
      } catch {
        // Reported once. The output stays open, so stop() still gives its file.
        m_hasFailed = true
        return error
      }
    }
    guard let failure else { return }

    m_onEvent(.terminated(failure))
  }

  // The loudest sample of the first channel.
  private static func peakDb(_ buffer: AVAudioPCMBuffer) -> Float {
    let frames = Int(buffer.frameLength)
    var peak: Float = 0

    if let samples = buffer.floatChannelData?[0] {
      for i in 0..<frames { peak = max(peak, abs(samples[i])) }
    } else if let samples = buffer.int16ChannelData?[0] {
      for i in 0..<frames { peak = max(peak, Float(samples[i].magnitude) / 32767) }
    }

    return peak > 0 ? 20 * log10(peak) : silenceDb
  }
}
