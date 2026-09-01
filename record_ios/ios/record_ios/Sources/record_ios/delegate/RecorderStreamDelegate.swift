import AVFoundation
import Foundation
import Flutter

class RecorderStreamDelegate: NSObject, AudioRecordingStreamDelegate {
  var config: RecordConfig?

  private var m_audioEngine: AVAudioEngine?
  private var m_processor: AudioStreamProcessor?
  private var m_isPaused = false
  private let m_lock = NSLock()
  private let m_bus = 0
  private let m_queue: DispatchQueue
  private let m_manageAudioSession: Bool
  private var m_onRecord: () -> ()
  private var m_onPause:  () -> ()
  private var m_onStop:   () -> ()
  private var m_interruptionObserver: NSObjectProtocol?

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
    // Configure the audio session before creating the engine: category /
    // activation / preferred sample rate changes may trigger an asynchronous
    // hardware sample rate switch, and an engine created beforehand can end
    // up observing a stale input format.
    m_interruptionObserver = try initAVAudioSession(config: config, manageAudioSession: m_manageAudioSession, queue: m_queue)

    // Wait for the input format to settle before installing the tap.
    // While a hardware sample rate switch (session reconfiguration, Bluetooth
    // HFP/A2DP negotiation, headphone route change) is still in progress,
    // inputFormat(forBus:) can return a stale sample rate. installTap then
    // hits the AVFAudio assertion
    //   'required condition is false: format.sampleRate == hwFormat.sampleRate'
    // which is raised as an NSException — uncatchable from Swift — and aborts
    // the process (SIGABRT). The engine is re-created on each retry because
    // the input node caches the format it first observed.
    var engine = AVAudioEngine()
    try setVoiceProcessing(echoCancel: config.echoCancel, autoGain: config.autoGain, audioEngine: engine)
    var srcFormat = engine.inputNode.inputFormat(forBus: m_bus)
    var tries = 0
    while !isFormatSettled(srcFormat, config: config), tries < 10 {
      // Runs on the plugin's background serial queue, not the main thread.
      usleep(25_000)
      engine = AVAudioEngine()
      try setVoiceProcessing(echoCancel: config.echoCancel, autoGain: config.autoGain, audioEngine: engine)
      srcFormat = engine.inputNode.inputFormat(forBus: m_bus)
      tries += 1
    }
    guard srcFormat.sampleRate > 0, srcFormat.channelCount > 0 else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Input format unavailable (rate=\(srcFormat.sampleRate), ch=\(srcFormat.channelCount))"
      )
    }

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
    m_onRecord()
  }

  // Whether the input format is usable for installTap: non-zero, and (unless
  // voice processing is enabled) matching the session's hardware sample rate.
  // With voice processing enabled the input node format may legitimately
  // differ from the hardware sample rate.
  private func isFormatSettled(_ format: AVAudioFormat, config: RecordConfig) -> Bool {
    guard format.sampleRate > 0, format.channelCount > 0 else { return false }
    guard !config.echoCancel else { return true }
    return abs(format.sampleRate - AVAudioSession.sharedInstance().sampleRate) < 1.0
  }

  @discardableResult
  func stop() -> String? {
    if let observer = m_interruptionObserver {
      NotificationCenter.default.removeObserver(observer)
      m_interruptionObserver = nil
    }

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
