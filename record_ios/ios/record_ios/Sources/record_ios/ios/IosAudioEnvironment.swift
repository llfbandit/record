import AVFoundation

// Owns the shared AVAudioSession of one recorder and its interruption observer.
final class IosAudioEnvironment: AudioEnvironment {
  var onEvent: ((EnvironmentEvent) -> Void)?

  // When false, the host app sets the category and activates the session itself.
  var manageAudioSession = true

  private let m_devices: IosDeviceRegistry
  private var m_observer: NSObjectProtocol?

  init(devices: IosDeviceRegistry) {
    m_devices = devices
  }

  deinit {
    release()
  }

  func prepare(_ config: RecordConfig) throws {
    do {
      try configure(config)
    } catch {
      // A half ready session is worse. The observer would stay for a take that never started.
      release()
      throw error
    }
  }

  func activate() throws {
    try AVAudioSession.sharedInstance().setActive(true)
  }

  func release() {
    guard let observer = m_observer else { return }

    NotificationCenter.default.removeObserver(observer)
    m_observer = nil
  }

  // MARK: - The `ios.*` channel calls

  func setSessionActive(_ active: Bool) throws {
    try AVAudioSession.sharedInstance().setActive(active)
  }

  func setSessionCategory(
    _ category: AVAudioSession.Category,
    options: AVAudioSession.CategoryOptions
  ) throws {
    try AVAudioSession.sharedInstance().setCategory(category, options: options)
  }

  // MARK: - Private

  private func configure(_ config: RecordConfig) throws {
    let session = AVAudioSession.sharedInstance()
    let iosConfig = config.iosConfig

    try applyPreferredSampleRate(config.sampleRate, session: session)
    try applyInterruptionPreference(suppressAlerts: config.audioInterruption == .none, session: session)

    if manageAudioSession {
      try applyCategory(AVAudioSession.CategoryOptions(iosConfig.categoryOptions), session: session)
      try activateForRecording(session)
    }

    try applyHapticsPreference(iosConfig.allowHapticsAndSystemSoundsDuringRecording, session: session)
    try applyPreferredChannelCount(config.numChannels, session: session)
    try applyPreferredInputDevice(config.device)

    m_observer = observeInterruptions()
  }

  private func applyPreferredSampleRate(_ sampleRate: Int, session: AVAudioSession) throws {
    do {
      try session.setPreferredSampleRate(min(Double(sampleRate), 48000.0))
    } catch {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "setPreferredSampleRate: \(error.localizedDescription)"
      )
    }
  }

  private func applyInterruptionPreference(suppressAlerts: Bool, session: AVAudioSession) throws {
    guard #available(iOS 14.5, *) else { return }

    do {
      try session.setPrefersNoInterruptionsFromSystemAlerts(suppressAlerts)
    } catch {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "setPrefersNoInterruptionsFromSystemAlerts: \(error.localizedDescription)"
      )
    }
  }

  private func applyCategory(_ options: AVAudioSession.CategoryOptions, session: AVAudioSession) throws {
    do {
      try session.setCategory(.playAndRecord, options: options)
    } catch {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "setCategory: \(error.localizedDescription)"
      )
    }
  }

  private func activateForRecording(_ session: AVAudioSession) throws {
    do {
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "setActive: \(error.localizedDescription)"
      )
    }
  }

  private func applyHapticsPreference(_ allow: Bool, session: AVAudioSession) throws {
    guard #available(iOS 13.0, *) else { return }

    do {
      try session.setAllowHapticsAndSystemSoundsDuringRecording(allow)
    } catch {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "setAllowHapticsAndSystemSoundsDuringRecording: \(error.localizedDescription)"
      )
    }
  }

  private func applyPreferredChannelCount(_ numChannels: Int, session: AVAudioSession) throws {
    let count = min(numChannels, session.maximumInputNumberOfChannels)
    guard count > 0 else { return }

    do {
      try session.setPreferredInputNumberOfChannels(count)
    } catch {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "setPreferredInputNumberOfChannels: \(error.localizedDescription)"
      )
    }
  }

  private func applyPreferredInputDevice(_ device: Device?) throws {
    guard let device else { return }
    guard let match = try m_devices.ports().first(where: { $0.uid == device.id }) else { return }

    do {
      try AVAudioSession.sharedInstance().setPreferredInput(match)
    } catch {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "setPreferredInput: \(error.localizedDescription)"
      )
    }
  }

  private func observeInterruptions() -> NSObjectProtocol {
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      guard let event = IosAudioEnvironment.event(from: notification) else { return }
      self?.onEvent?(event)
    }
  }

  // Reads the notification. Nil when there is nothing to do.
  private static func event(from notification: Notification) -> EnvironmentEvent? {
    guard let info = notification.userInfo,
          let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }

    switch type {
    case .began:
      return .interrupted

    case .ended:
      let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
        .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
      return .interruptionEnded(shouldResume: options.contains(.shouldResume))

    default:
      return nil
    }
  }
}
