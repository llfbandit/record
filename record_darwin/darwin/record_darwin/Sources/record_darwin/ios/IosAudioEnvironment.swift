#if os(iOS)

import AVFoundation

// Owns the AVAudioSession and its interruption observer.
final class IosAudioEnvironment: AudioEnvironment {
  // When false, the app sets the category and activates itself.
  var manageAudioSession = true

  private let m_devices: IosDeviceRegistry
  // Never nil. The observer thread may read it at any time.
  private var m_onEvent: (EnvironmentEvent) -> Void = { _ in }
  private var m_observer: NSObjectProtocol?
  // The input we chose for this take. release() clears it.
  private var m_preferredInputUid: String?
  // The app's value before the take. release() puts it back.
  private var m_appPrefersNoInterruptions: Bool?

  init(devices: IosDeviceRegistry) {
    m_devices = devices
  }

  func bind(onEvent: @escaping (EnvironmentEvent) -> Void) {
    m_onEvent = onEvent
  }

  deinit {
    release()
  }

  func prepare(_ config: RecordConfig) throws {
    do {
      try configure(config)
    } catch {
      // Else the observer would stay for a take that never started.
      release()
      throw error
    }
  }

  func activate() throws {
    try setSessionActive(true)
  }

  func release() {
    let session = AVAudioSession.sharedInstance()

    // Only if it is still ours. The app may have changed it since.
    if let uid = m_preferredInputUid {
      m_preferredInputUid = nil
      if session.preferredInput?.uid == uid { try? session.setPreferredInput(nil) }
    }
    if #available(iOS 14.5, *), let appValue = m_appPrefersNoInterruptions {
      m_appPrefersNoInterruptions = nil
      if session.prefersNoInterruptionsFromSystemAlerts { try? session.setPrefersNoInterruptionsFromSystemAlerts(appValue) }
    }

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

    try RecorderError.wrapping("setPreferredSampleRate") {
      try session.setPreferredSampleRate(min(Double(config.sampleRate), 48000.0))
    }

    if manageAudioSession {
      // A ringing call only shows a banner. The take is interrupted only when the call is answered.
      if #available(iOS 14.5, *) {
        let appValue = session.prefersNoInterruptionsFromSystemAlerts
        try RecorderError.wrapping("setPrefersNoInterruptionsFromSystemAlerts") {
          try session.setPrefersNoInterruptionsFromSystemAlerts(true)
        }
        m_appPrefersNoInterruptions = appValue
      }
      try RecorderError.wrapping("setCategory") {
        try session.setCategory(.playAndRecord, options: iosConfig.categoryOptions)
      }
      try RecorderError.wrapping("setActive") {
        try session.setActive(true, options: .notifyOthersOnDeactivation)
      }
    }

    if #available(iOS 13.0, *) {
      try RecorderError.wrapping("setAllowHapticsAndSystemSoundsDuringRecording") {
        try session.setAllowHapticsAndSystemSoundsDuringRecording(iosConfig.allowHapticsAndSystemSoundsDuringRecording)
      }
    }

    // Input first. It changes the route, and the channel limit depends on the route.
    let port = try config.device.flatMap { device in
      try m_devices.ports().first { $0.uid == device.id }
    }
    if let port {
      try RecorderError.wrapping("setPreferredInput") { try session.setPreferredInput(port) }
      m_preferredInputUid = port.uid
    }

    let channels = min(config.numChannels, session.maximumInputNumberOfChannels)
    if channels > 0 {
      try RecorderError.wrapping("setPreferredInputNumberOfChannels") {
        try session.setPreferredInputNumberOfChannels(channels)
      }
    }

    m_observer = observeInterruptions()
  }

  private func observeInterruptions() -> NSObjectProtocol {
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      guard let event = IosAudioEnvironment.event(from: notification) else { return }
      self?.m_onEvent(event)
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

#endif
