import AVFoundation

// One AVAudioEngine on one input, with its tap set.
final class EngineInput {
  // What the tap gives.
  let format: AVAudioFormat

  private let m_engine: AVAudioEngine
  private let m_usesVoiceProcessing: Bool
  private let m_observer: NSObjectProtocol

  private static let bus = 0

  // Binds a new engine to the input and taps it. Nil is the default input. The engine is not started.
  // onBuffer runs on the tap thread. onStop runs on any thread, when the system stops the engine.
  static func open(
    on deviceId: String?,
    config: RecordConfig,
    route: InputRoute,
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
    onStop: @escaping () -> Void
  ) throws -> EngineInput {
    let engine = AVAudioEngine()
    // Auto gain works only with voice processing on, and voice processing always cancels echo.
    let usesVoiceProcessing = config.echoCancel || config.autoGain

    do {
      try route.bind(deviceId, channels: config.numChannels, to: engine)
      // A new engine starts with voice processing off.
      if usesVoiceProcessing { try setVoiceProcessing(true, autoGain: config.autoGain, on: engine) }

      let format = engine.inputNode.inputFormat(forBus: bus)
      // A tap on this format would crash the app.
      guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }

      engine.inputNode.installTap(
        onBus: bus,
        bufferSize: AVAudioFrameCount(config.streamBufferSize ?? 1024),
        format: format
      ) { buffer, _ in
        onBuffer(buffer)
      }
      engine.prepare()

      // The system stops the engine when the input changes (device unplugged, new route).
      let observer = NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
      ) { [weak engine] _ in
        if engine?.isRunning == false { onStop() }
      }

      return EngineInput(engine: engine, format: format, usesVoiceProcessing: usesVoiceProcessing, observer: observer)
    } catch {
      // Leave nothing behind: no tap, no voice processing.
      shutDown(engine, usesVoiceProcessing: usesVoiceProcessing)
      throw error
    }
  }

  private init(engine: AVAudioEngine, format: AVAudioFormat, usesVoiceProcessing: Bool, observer: NSObjectProtocol) {
    m_engine = engine
    self.format = format
    m_usesVoiceProcessing = usesVoiceProcessing
    m_observer = observer
  }

  // Still in the tap format. Else starting it would crash the app.
  var isCurrent: Bool {
    let now = m_engine.inputNode.inputFormat(forBus: Self.bus)
    return now.sampleRate == format.sampleRate && now.channelCount == format.channelCount
  }

  func start() throws {
    try m_engine.start()
  }

  func pause() {
    m_engine.pause()
  }

  // Frees the engine: no observer, no tap, no voice processing. It cannot be used again.
  func close() {
    NotificationCenter.default.removeObserver(m_observer)
    Self.shutDown(m_engine, usesVoiceProcessing: m_usesVoiceProcessing)
  }

  // MARK: - Private

  private static func shutDown(_ engine: AVAudioEngine, usesVoiceProcessing: Bool) {
    engine.inputNode.removeTap(onBus: bus)
    engine.stop()
    // Voice processing can only change on a stopped engine.
    if usesVoiceProcessing { try? setVoiceProcessing(false, autoGain: false, on: engine) }
  }

  private static func setVoiceProcessing(_ enabled: Bool, autoGain: Bool, on engine: AVAudioEngine) throws {
    guard #available(iOS 13.0, *) else { return }

    try RecorderError.wrapping("setVoiceProcessingEnabled", failure: "Failed to setup voice processing") {
      try engine.inputNode.setVoiceProcessingEnabled(enabled)
    }
    engine.inputNode.isVoiceProcessingAGCEnabled = enabled && autoGain
  }
}
