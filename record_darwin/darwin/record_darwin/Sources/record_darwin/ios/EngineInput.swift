#if os(iOS)

import AVFoundation

// One AVAudioEngine on the session input, with its tap set.
final class EngineInput: CaptureInput {
  // What the tap gives.
  let format: AVAudioFormat

  private let m_engine: AVAudioEngine
  private let m_usesVoiceProcessing: Bool
  private let m_observer: NSObjectProtocol

  private static let bus = 0

  // A new engine, tapped. See OpenInput.
  // onChange comes when the engine's configuration changes.
  static func open(
    config: RecordConfig,
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
    onChange: @escaping () -> Void
  ) throws -> EngineInput {
    let engine = AVAudioEngine()
    let usesVoiceProcessing = config.usesVoiceProcessing

    do {
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

      // We listen last, so our own setup does not report a change.
      let observer = NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
      ) { _ in
        onChange()
      }

      return EngineInput(
        engine: engine, format: format, usesVoiceProcessing: usesVoiceProcessing, observer: observer
      )
    } catch {
      // Leave nothing behind: no tap, no voice processing.
      shutDown(engine, usesVoiceProcessing: usesVoiceProcessing)
      throw error
    }
  }

  private init(
    engine: AVAudioEngine,
    format: AVAudioFormat,
    usesVoiceProcessing: Bool,
    observer: NSObjectProtocol
  ) {
    m_engine = engine
    self.format = format
    m_usesVoiceProcessing = usesVoiceProcessing
    m_observer = observer
  }

  var isRunning: Bool { m_engine.isRunning }

  // Still in the tap format. Else starting it would crash the app.
  var isCurrent: Bool {
    m_engine.inputNode.inputFormat(forBus: Self.bus).hasSameLayout(as: format)
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
    keepAlive(engine)
  }

  private static let closedEngines = DispatchQueue(label: "com.record.closedEngines")

  // A device change queues blocks that use the engine's IO unit, but they do not keep the engine alive.
  // If we free the engine before they run, the app crashes (seen with Bluetooth buds).
  // So we keep it 3 seconds more.
  private static func keepAlive(_ engine: AVAudioEngine) {
    closedEngines.asyncAfter(deadline: .now() + 3) { withExtendedLifetime(engine) {} }
  }

  private static func setVoiceProcessing(_ enabled: Bool, autoGain: Bool, on engine: AVAudioEngine) throws {
    guard #available(iOS 13.0, *) else { return }

    try RecorderError.wrapping("setVoiceProcessingEnabled", failure: "Failed to setup voice processing") {
      try engine.inputNode.setVoiceProcessingEnabled(enabled)
    }
    engine.inputNode.isVoiceProcessingAGCEnabled = enabled && autoGain
  }
}

#endif
