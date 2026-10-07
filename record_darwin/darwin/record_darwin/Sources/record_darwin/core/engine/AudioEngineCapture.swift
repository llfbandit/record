import AVFoundation

// Where a take sends its audio.
enum CaptureTarget {
  case stream
  case file(path: String)
}

// Runs one take: an output fed by an EngineInput. File and stream takes use it, on iOS and macOS.
// The tap runs on its own thread, so we lock.
final class AudioEngineCapture: CaptureEngine {
  private let m_config: RecordConfig
  private let m_target: CaptureTarget
  private let m_route: InputRoute
  private let m_onEvent: (CaptureEvent) -> Void
  private let m_lock = NSLock()

  private var m_engine: EngineInput?
  private var m_output: CaptureOutput?
  private var m_isPaused = false
  private var m_amplitude = silenceDb

  init(
    config: RecordConfig,
    target: CaptureTarget,
    route: InputRoute,
    onEvent: @escaping (CaptureEvent) -> Void
  ) {
    m_config = config
    m_target = target
    m_route = route
    m_onEvent = onEvent
  }

  func start() throws -> RecordConfig {
    if case .file(let path) = m_target { try RecordFile.delete(at: path) }

    do {
      let engine = try EngineInput.open(
        on: m_config.device?.id,
        config: m_config,
        route: m_route,
        onBuffer: { [weak self] in self?.handleTap($0) },
        onStop: { [weak self] in self?.handleEngineStop() }
      )
      m_engine = engine

      let negotiated = try FormatPolicy.negotiate(for: m_config, input: engine.format)
      let output = try makeOutput(settings: negotiated.settings, config: negotiated.effective, srcFormat: engine.format)
      m_lock.withLock { m_output = output }

      try engine.start()
      return negotiated.effective
    } catch {
      // Leave nothing behind: no engine, no file.
      stop(delete: true)
      throw error
    }
  }

  func pause() {
    m_lock.withLock { m_isPaused = true }
    m_engine?.pause()
  }

  // Starts the engine again after a pause. It writes to the same file, so nothing is lost.
  func resume() throws {
    guard let engine = m_engine else { return }

    // The input changed during the pause. Starting with the old tap format would crash the app.
    guard engine.isCurrent else {
      let error = Self.inputChangedError
      terminate(error)
      throw error
    }

    try engine.start()
    m_lock.withLock { m_isPaused = false }
  }

  @discardableResult
  func stop(delete: Bool) -> String? {
    m_engine?.close()
    m_engine = nil
    m_route.release()

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

  // The engine stopped by itself. End the take and keep the file.
  // A paused engine is never running, so resume() checks the input instead.
  private func handleEngineStop() {
    guard !m_lock.withLock({ m_isPaused }) else { return }
    terminate(Self.inputChangedError)
  }

  // Closes the output, keeps the file, and tells the controller once.
  private func terminate(_ error: Error) {
    let output = m_lock.withLock { () -> CaptureOutput? in
      let output = m_output
      m_output = nil
      return output
    }
    guard let output else { return }

    _ = output.close(delete: false)
    m_onEvent(.terminated(error))
  }

  private static let inputChangedError = RecorderError.error(
    message: "Recording stopped",
    details: "The audio input changed or is gone."
  )

  // Runs under the lock, so stop() cannot close the output during a write.
  private func handleTap(_ buffer: AVAudioPCMBuffer) {
    let failure = m_lock.withLock { () -> (CaptureOutput, Error)? in
      guard !m_isPaused, let output = m_output else { return nil }

      m_amplitude = Self.peakDb(buffer)
      do {
        try output.write(buffer)
        return nil
      } catch {
        // Clear it, so the next buffer does not report the error again.
        m_output = nil
        return (output, error)
      }
    }
    guard let failure else { return }

    // Keeps what was written before.
    _ = failure.0.close(delete: false)
    m_onEvent(.terminated(failure.1))
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
