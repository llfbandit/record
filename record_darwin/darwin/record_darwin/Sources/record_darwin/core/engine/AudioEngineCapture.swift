import AVFoundation

// Where a take sends its audio.
enum CaptureTarget {
  case stream
  case file(path: String)
}

extension CaptureTarget {
  func makeOutput(
    settings: [String: Any],
    config: RecordConfig,
    srcFormat: AVAudioFormat,
    onEvent: @escaping (CaptureEvent) -> Void
  ) throws -> CaptureOutput {
    switch self {
    case .stream:
      let processor = try AudioStreamProcessor(config: config, srcFormat: srcFormat)
      return StreamOutput(processor: processor) { onEvent(.chunk($0)) }

    case .file(let path):
      // pcm16bits has no container. We write the raw stream bytes.
      guard let fileType = FormatPolicy.fileType(for: config.encoder) else {
        let processor = try AudioStreamProcessor(config: config, srcFormat: srcFormat)
        return try RawFileOutput(path: path, processor: processor)
      }
      return try AudioFileOutput(path: path, settings: settings, fileType: fileType, srcFormat: srcFormat)
    }
  }
}

// Captures with AVAudioEngine and gives each buffer to an output.
// File and stream takes use it, on iOS and macOS. The tap runs on its own thread, so we lock.
final class AudioEngineCapture: CaptureEngine {
  private let m_config: RecordConfig
  private let m_target: CaptureTarget
  private let m_environment: AudioEnvironment
  private let m_onEvent: (CaptureEvent) -> Void
  private let m_bus = 0
  private let m_lock = NSLock()

  private var m_audioEngine: AVAudioEngine?
  private var m_configObserver: NSObjectProtocol?
  private var m_output: CaptureOutput?
  // The format the tap was installed with.
  private var m_tapFormat: AVAudioFormat?
  private var m_isPaused = false
  private var m_amplitude = silenceDb

  init(
    config: RecordConfig,
    target: CaptureTarget,
    environment: AudioEnvironment,
    onEvent: @escaping (CaptureEvent) -> Void
  ) {
    m_config = config
    m_target = target
    m_environment = environment
    m_onEvent = onEvent
  }

  func start() throws -> RecordConfig {
    if case .file(let path) = m_target { try RecordFile.delete(at: path) }

    let engine = AVAudioEngine()
    var output: CaptureOutput?
    let effective: RecordConfig

    do {
      try m_environment.bindInput(m_config.device, to: engine.inputNode)
      // A new engine starts with voice processing off.
      if usesVoiceProcessing { try setVoiceProcessing(true, on: engine) }

      let srcFormat = engine.inputNode.inputFormat(forBus: m_bus)
      // A tap on this format would crash the app.
      guard srcFormat.sampleRate > 0, srcFormat.channelCount > 0 else {
        throw RecorderError.startFailed("No audio input is available.")
      }

      let negotiated = try FormatPolicy.negotiate(for: m_config, input: srcFormat)
      effective = negotiated.effective
      output = try m_target.makeOutput(settings: negotiated.settings, config: effective, srcFormat: srcFormat, onEvent: m_onEvent)

      engine.inputNode.installTap(
        onBus: m_bus,
        bufferSize: AVAudioFrameCount(m_config.streamBufferSize ?? 1024),
        format: srcFormat
      ) { [weak self] buffer, _ in
        self?.handleTap(buffer)
      }
      m_tapFormat = srcFormat

      engine.prepare()
      try engine.start()
    } catch {
      // Leave nothing behind: no tap, no voice processing, no file.
      shutDown(engine)
      _ = output?.close(delete: true)
      throw error
    }

    m_audioEngine = engine
    m_lock.withLock { m_output = output }

    // The system stops the engine when the input changes (device unplugged, new route).
    m_configObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
    ) { [weak self, weak engine] _ in
      guard let engine else { return }
      self?.handleConfigurationChange(engine)
    }
    // It may have stopped before we started to listen.
    handleConfigurationChange(engine)

    return effective
  }

  func pause() {
    m_lock.withLock { m_isPaused = true }
    m_audioEngine?.pause()
  }

  // Starts the engine again after a pause. It writes to the same file, so nothing is lost.
  func resume() throws {
    guard let engine = m_audioEngine, let tapFormat = m_tapFormat else { return }

    // The input changed during the pause. Starting with the old tap format would crash the app.
    let input = engine.inputNode.inputFormat(forBus: m_bus)
    if input.sampleRate != tapFormat.sampleRate || input.channelCount != tapFormat.channelCount {
      let error = Self.inputChangedError
      terminate(error)
      throw error
    }

    try engine.start()
    m_lock.withLock { m_isPaused = false }
  }

  @discardableResult
  func stop(delete: Bool) -> String? {
    if let observer = m_configObserver {
      NotificationCenter.default.removeObserver(observer)
      m_configObserver = nil
    }
    if let engine = m_audioEngine { shutDown(engine) }
    m_audioEngine = nil

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

  private func shutDown(_ engine: AVAudioEngine) {
    engine.inputNode.removeTap(onBus: m_bus)
    engine.stop()
    // Voice processing can only change on a stopped engine.
    if usesVoiceProcessing { try? setVoiceProcessing(false, on: engine) }
  }

  // The engine stopped by itself. End the take and keep the file.
  // A paused engine is never running, so resume() checks the input instead.
  private func handleConfigurationChange(_ engine: AVAudioEngine) {
    guard !engine.isRunning, !m_lock.withLock({ m_isPaused }) else { return }
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
  static func peakDb(_ buffer: AVAudioPCMBuffer) -> Float {
    let frames = Int(buffer.frameLength)
    var peak: Float = 0

    if let samples = buffer.floatChannelData?[0] {
      for i in 0..<frames { peak = max(peak, abs(samples[i])) }
    } else if let samples = buffer.int16ChannelData?[0] {
      for i in 0..<frames { peak = max(peak, Float(samples[i].magnitude) / 32767) }
    }

    return peak > 0 ? 20 * log10(peak) : silenceDb
  }

  private var usesVoiceProcessing: Bool { m_config.echoCancel || m_config.autoGain }

  // Auto gain works only with voice processing on, and voice processing always cancels echo.
  private func setVoiceProcessing(_ enabled: Bool, on engine: AVAudioEngine) throws {
    guard #available(iOS 13.0, *) else { return }

    try RecorderError.wrapping("setVoiceProcessingEnabled", failure: "Failed to setup voice processing") {
      try engine.inputNode.setVoiceProcessingEnabled(enabled)
    }
    engine.inputNode.isVoiceProcessingAGCEnabled = enabled && m_config.autoGain
  }
}
