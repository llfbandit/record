import AVFoundation
import Foundation
import Flutter

class RecorderStreamDelegate: NSObject, AudioRecordingStreamDelegate {
  var config: RecordConfig?

  private var m_audioEngine: AVAudioEngine?
  private var m_processor: AudioStreamProcessor?
  private var m_isPaused = false
  private var m_recordEventHandler: RecordStreamHandler?
  private let m_lock = NSLock()
  private let m_bus = 0
  private let m_queue: DispatchQueue
  private let m_manageAudioSession: Bool
  private var m_onRecord: () -> ()
  private var m_onPause:  () -> ()
  private var m_onStop:   () -> ()
  private var m_interruptionObserver: NSObjectProtocol?
  private var m_configChangeObserver: NSObjectProtocol?

  init(
    queue: DispatchQueue,
    manageAudioSession: Bool,
    onRecord: @escaping () -> (),
    onPause:  @escaping () -> (),
    onStop:   @escaping () -> ()
  ) {
    m_queue = queue
    m_manageAudioSession = manageAudioSession
    m_onRecord = onRecord
    m_onPause  = onPause
    m_onStop   = onStop
  }

  func start(config: RecordConfig, recordEventHandler: RecordStreamHandler) throws {
    let engine = AVAudioEngine()
    m_interruptionObserver = try initAVAudioSession(config: config, manageAudioSession: m_manageAudioSession, queue: m_queue)
    try setVoiceProcessing(echoCancel: config.echoCancel, autoGain: config.autoGain, audioEngine: engine)

    let srcFormat = engine.inputNode.inputFormat(forBus: 0)
    let processor = try AudioStreamProcessor(config: config, srcFormat: srcFormat)

    engine.inputNode.installTap(
      onBus: m_bus,
      bufferSize: AVAudioFrameCount(config.streamBufferSize ?? 1024),
      format: srcFormat
    ) { [weak self] buffer, _ in
      self?.handleTap(buffer: buffer, recordEventHandler: recordEventHandler)
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      processor.dispose()
      throw error
    }

    m_audioEngine = engine
    m_lock.withLock { m_processor = processor }
    self.config = config
    m_recordEventHandler = recordEventHandler

    if config.iosConfig.restartOnEngineConfigurationChange {
      m_configChangeObserver = NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange,
        object: engine,
        queue: nil
      ) { [weak self] _ in
        self?.m_queue.async { self?.restartAfterConfigurationChange() }
      }
    }

    m_onRecord()
  }

  @discardableResult
  func stop() -> String? {
    if let observer = m_interruptionObserver {
      NotificationCenter.default.removeObserver(observer)
      m_interruptionObserver = nil
    }
    if let observer = m_configChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      m_configChangeObserver = nil
    }
    m_recordEventHandler = nil

    if let engine = m_audioEngine {
      do { try setVoiceProcessing(echoCancel: false, autoGain: false, audioEngine: engine) } catch {}
      engine.inputNode.removeTap(onBus: m_bus)
      engine.stop()
    }
    m_audioEngine = nil

    m_lock.withLock {
      m_isPaused = false
      m_processor?.dispose()
      m_processor = nil
    }

    config = nil
    m_onStop()
    return nil
  }

  func pause() {
    m_lock.withLock { m_isPaused = true }
    m_audioEngine?.pause()
    m_onPause()
  }

  func resume() throws {
    try m_audioEngine?.start()
    m_lock.withLock { m_isPaused = false }
    m_onRecord()
  }

  func cancel() throws { _ = stop() }

  func getAmplitude() -> Float {
    m_lock.withLock { m_processor?.getAmplitude() ?? -160.0 }
  }

  func dispose() { _ = stop() }

  // MARK: - Private

  private func handleTap(buffer: AVAudioPCMBuffer, recordEventHandler: RecordStreamHandler) {
    let processor = m_lock.withLock { m_isPaused ? nil : m_processor }

    guard let processor else { return }

    guard let dataList = processor.process(buffer: buffer) else {
      let toDispose = m_lock.withLock { () -> AudioStreamProcessor? in
        let p = m_processor
        m_processor = nil
        return p
      }
      guard toDispose != nil else { return }
      m_queue.async {
        toDispose?.dispose()
        self.stop()
      }
      return
    }

    guard let sink = recordEventHandler.eventSink else { return }
    for data in dataList {
      DispatchQueue.main.async { sink(FlutterStandardTypedData(bytes: data)) }
    }
  }

  // The engine does not restart itself after a configuration change (route
  // change, another app reconfiguring the shared session) — the tap must be
  // reinstalled against the new format and the engine started again.
  private func restartAfterConfigurationChange() {
    guard !m_lock.withLock({ m_isPaused }),
          let engine = m_audioEngine,
          let config,
          let recordEventHandler = m_recordEventHandler else { return }

    engine.inputNode.removeTap(onBus: m_bus)

    // Before the new format is read, not after: the tap has to be installed
    // against the input this session actually ends up on. If the route is still
    // settling and the format read below is the outgoing device's, the move
    // posts a further configuration change and this runs again — that second
    // pass finds the wanted input already current, skips the re-pin, and
    // installs the tap against the settled format.
    reapplyPreferredInputDevice(config.device)

    let format = engine.inputNode.inputFormat(forBus: 0)

    do {
      let processor = try AudioStreamProcessor(config: config, srcFormat: format)
      engine.inputNode.installTap(
        onBus: m_bus,
        bufferSize: AVAudioFrameCount(config.streamBufferSize ?? 1024),
        format: format
      ) { [weak self] buffer, _ in
        self?.handleTap(buffer: buffer, recordEventHandler: recordEventHandler)
      }
      m_lock.withLock { m_processor = processor }
      engine.prepare()
      try engine.start()
      m_onRecord()
    } catch {
      _ = stop()
    }
  }

  private func setVoiceProcessing(echoCancel: Bool, autoGain: Bool, audioEngine: AVAudioEngine) throws {
    if #available(iOS 13.0, *) {
      do {
        try audioEngine.inputNode.setVoiceProcessingEnabled(echoCancel)
        audioEngine.inputNode.isVoiceProcessingAGCEnabled = autoGain
      } catch {
        throw RecorderError.error(
          message: "Failed to setup voice processing",
          details: "Echo cancel error: \(error)"
        )
      }
    }
  }
}
