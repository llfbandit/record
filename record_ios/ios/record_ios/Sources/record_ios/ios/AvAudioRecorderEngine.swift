import AVFoundation

// Records to a file. AVAudioRecorder encodes and writes it.
final class AvAudioRecorderEngine: NSObject, CaptureEngine, AVAudioRecorderDelegate {
  private let m_config: RecordConfig
  private let m_path: String
  private let m_devices: DeviceRegistry
  private let m_onEvent: (CaptureEvent) -> Void

  private var m_recorder: AVAudioRecorder?

  init(
    config: RecordConfig,
    path: String,
    devices: DeviceRegistry,
    onEvent: @escaping (CaptureEvent) -> Void
  ) {
    m_config = config
    m_path = path
    m_devices = devices
    m_onEvent = onEvent
  }

  func start() throws -> RecordConfig {
    try deleteFile()

    // This reads the current route, so the audio session must be ready.
    let (settings, effective) = try FormatNegotiator.outputSettings(for: m_config, devices: m_devices)

    let recorder = try AVAudioRecorder(url: URL(fileURLWithPath: m_path), settings: settings)
    recorder.delegate = self
    recorder.isMeteringEnabled = true
    recorder.prepareToRecord()
    recorder.record()

    m_recorder = recorder

    return effective
  }

  func pause() -> Bool {
    guard let recorder = m_recorder, recorder.isRecording else { return false }

    recorder.pause()
    return true
  }

  func resume() throws -> Bool {
    guard let recorder = m_recorder else { return false }

    recorder.record()
    return true
  }

  @discardableResult
  func stop(delete: Bool) -> String? {
    guard let recorder = m_recorder else { return nil }

    // Detach first, so our own stop does not come back as a system stop.
    recorder.delegate = nil
    recorder.stop()
    m_recorder = nil

    if delete {
      try? deleteFile()
      return nil
    }
    return m_path
  }

  var amplitude: Float {
    guard let recorder = m_recorder else { return silenceDb }

    recorder.updateMeters()
    return recorder.averagePower(forChannel: 0)
  }

  // Called only when nobody asked to stop: disk full, route lost, hardware error.
  func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    m_onEvent(.terminated(flag ? nil : RecorderError.error(
      message: "Recording stopped",
      details: "The system ended the recording."
    )))
  }

  // MARK: - Private

  private func deleteFile() throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: m_path) else { return }

    do {
      try fileManager.removeItem(atPath: m_path)
    } catch {
      throw RecorderError.error(
        message: "Failed to delete previous recording",
        details: error.localizedDescription
      )
    }
  }
}
