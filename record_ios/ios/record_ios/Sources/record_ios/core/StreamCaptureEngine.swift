import AVFoundation

// Captures with AVAudioEngine. The tap runs on a render thread, so we need the lock.
final class StreamCaptureEngine: CaptureEngine {
  private let m_config: RecordConfig
  private let m_environment: AudioEnvironment
  private let m_onEvent: (CaptureEvent) -> Void
  private let m_bus = 0
  private let m_lock = NSLock()

  private var m_audioEngine: AVAudioEngine?
  private var m_processor: AudioStreamProcessor?
  private var m_isPaused = false

  init(
    config: RecordConfig,
    environment: AudioEnvironment,
    onEvent: @escaping (CaptureEvent) -> Void
  ) {
    m_config = config
    m_environment = environment
    m_onEvent = onEvent
  }

  func start() throws -> RecordConfig {
    let engine = AVAudioEngine()

    try m_environment.bindInput(m_config.device, to: engine.inputNode)
    try setVoiceProcessing(echoCancel: m_config.echoCancel, autoGain: m_config.autoGain, on: engine)

    let srcFormat = engine.inputNode.inputFormat(forBus: m_bus)
    let processor = try AudioStreamProcessor(config: m_config, srcFormat: srcFormat)

    engine.inputNode.installTap(
      onBus: m_bus,
      bufferSize: AVAudioFrameCount(m_config.streamBufferSize ?? 1024),
      format: srcFormat
    ) { [weak self] buffer, _ in
      self?.handleTap(buffer)
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      engine.inputNode.removeTap(onBus: m_bus)
      processor.dispose()
      throw error
    }

    m_audioEngine = engine
    m_lock.withLock { m_processor = processor }

    // The stream path never negotiates the format.
    return m_config
  }

  func pause() -> Bool {
    guard let engine = m_audioEngine else { return false }

    m_lock.withLock { m_isPaused = true }
    engine.pause()
    return true
  }

  func resume() throws -> Bool {
    guard let engine = m_audioEngine else { return false }

    try engine.start()
    m_lock.withLock { m_isPaused = false }
    return true
  }

  @discardableResult
  func stop(delete: Bool) -> String? {
    if let engine = m_audioEngine {
      do { try setVoiceProcessing(echoCancel: false, autoGain: false, on: engine) } catch {}
      engine.inputNode.removeTap(onBus: m_bus)
      engine.stop()
    }
    m_audioEngine = nil

    m_lock.withLock {
      m_isPaused = false
      m_processor?.dispose()
      m_processor = nil
    }

    // Nothing was written to disk.
    return nil
  }

  var amplitude: Float {
    m_lock.withLock { m_processor?.getAmplitude() ?? silenceDb }
  }

  // MARK: - Private

  private func handleTap(_ buffer: AVAudioPCMBuffer) {
    let processor = m_lock.withLock { m_isPaused ? nil : m_processor }
    guard let processor else { return }

    guard let chunks = processor.process(buffer: buffer) else {
      // Take it away, so the next buffer cannot report this error a second time.
      let lost = m_lock.withLock { () -> AudioStreamProcessor? in
        let p = m_processor
        m_processor = nil
        return p
      }
      guard let lost else { return }

      lost.dispose()
      m_onEvent(.terminated(RecorderError.error(
        message: "Recording stopped",
        details: "Audio format conversion failed."
      )))
      return
    }

    for chunk in chunks { m_onEvent(.chunk(chunk)) }
  }

  private func setVoiceProcessing(echoCancel: Bool, autoGain: Bool, on engine: AVAudioEngine) throws {
    guard #available(iOS 13.0, *) else { return }

    do {
      try engine.inputNode.setVoiceProcessingEnabled(echoCancel)
      engine.inputNode.isVoiceProcessingAGCEnabled = autoGain
    } catch {
      throw RecorderError.error(
        message: "Failed to setup voice processing",
        details: "Echo cancel error: \(error)"
      )
    }
  }
}
