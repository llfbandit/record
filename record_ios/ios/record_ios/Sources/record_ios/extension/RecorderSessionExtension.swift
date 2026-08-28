import AVFoundation

extension AudioRecordingDelegate {
  @discardableResult
  func initAVAudioSession(config: RecordConfig, manageAudioSession: Bool, queue: DispatchQueue) throws -> NSObjectProtocol {
    let session = AVAudioSession.sharedInstance()

    try applyPreferredSampleRate(config.sampleRate, session: session)
    try applyInterruptionPreference(suppressAlerts: config.audioInterruption == AudioInterruptionMode.none, session: session)

    if manageAudioSession {
      try applyCategory(AVAudioSession.CategoryOptions(config.iosConfig.categoryOptions), session: session)
      try activateSession(session)
    }

    try applyHapticsPreference(config.iosConfig.allowHapticsAndSystemSoundsDuringRecording, session: session)
    try applyPreferredChannelCount(config.numChannels, session: session)
    try applyPreferredInputDevice(config.device)

    return registerInterruptionObserver(queue: queue)
  }

  /// Re-asserts `config.device` after the route has moved underneath a live
  /// session.
  ///
  /// `setPreferredInput` is applied once, from `initAVAudioSession`, and iOS
  /// drops that preference when it re-routes — so a Bluetooth headset or
  /// CarPlay unit connecting mid-session captures the microphone for the rest
  /// of the recording even though a device was explicitly requested. Recording
  /// apps that must stay on the built-in mic have no way to express that today.
  ///
  /// Deliberately a no-op when the wanted input is already current: calling
  /// `setPreferredInput` forces a route change, which posts another
  /// configuration change, which would call straight back into here.
  func reapplyPreferredInputDevice(_ device: Device?) {
    guard let device else { return }

    let session = AVAudioSession.sharedInstance()
    if session.currentRoute.inputs.first?.uid == device.id { return }

    guard let inputs = session.availableInputs,
          let match = inputs.first(where: { $0.uid == device.id }) else { return }

    do {
      try session.setPreferredInput(match)
    } catch {
      print("Unable to reapply the preferred input: \(error.localizedDescription)")
    }
  }
}

// MARK: - Session configuration steps

private extension AudioRecordingDelegate {
  func applyPreferredSampleRate(_ sampleRate: Int, session: AVAudioSession) throws {
    do {
      try session.setPreferredSampleRate(min(Double(sampleRate), 48000.0))
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setPreferredSampleRate: \(error.localizedDescription)")
    }
  }

  func applyInterruptionPreference(suppressAlerts: Bool, session: AVAudioSession) throws {
    guard #available(iOS 14.5, *) else { return }
    do {
      try session.setPrefersNoInterruptionsFromSystemAlerts(suppressAlerts)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setPrefersNoInterruptionsFromSystemAlerts: \(error.localizedDescription)")
    }
  }

  func applyCategory(_ options: AVAudioSession.CategoryOptions, session: AVAudioSession) throws {
    do {
      try session.setCategory(.playAndRecord, options: options)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setCategory: \(error.localizedDescription)")
    }
  }

  func activateSession(_ session: AVAudioSession) throws {
    do {
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setActive: \(error.localizedDescription)")
    }
  }

  func applyHapticsPreference(_ allow: Bool, session: AVAudioSession) throws {
    guard #available(iOS 13.0, *) else { return }
    do {
      try session.setAllowHapticsAndSystemSoundsDuringRecording(allow)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setAllowHapticsAndSystemSoundsDuringRecording: \(error.localizedDescription)")
    }
  }

  func applyPreferredChannelCount(_ numChannels: Int, session: AVAudioSession) throws {
    let count = min(numChannels, session.maximumInputNumberOfChannels)
    guard count > 0 else { return }
    do {
      try session.setPreferredInputNumberOfChannels(count)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setPreferredInputNumberOfChannels: \(error.localizedDescription)")
    }
  }

  func applyPreferredInputDevice(_ device: Device?) throws {
    guard let device else { return }
    guard let inputs = try listInputDevices() else { return }
    guard let match = inputs.first(where: { $0.uid == device.id }) else { return }
    do {
      try AVAudioSession.sharedInstance().setPreferredInput(match)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setPreferredInput: \(error.localizedDescription)")
    }
  }

  func registerInterruptionObserver(queue: DispatchQueue) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      queue.async { self?.onAudioSessionInterruption(notification: notification) }
    }
  }
}

// MARK: - Interruption handling

private extension AudioRecordingDelegate {
  func onAudioSessionInterruption(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue),
          let config = self.config else { return }

    switch type {
    case .began:
      if config.audioInterruption != AudioInterruptionMode.none {
         pause()
      }
    case .ended:
      guard config.audioInterruption == AudioInterruptionMode.pauseResume,
            let optValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
            AVAudioSession.InterruptionOptions(rawValue: optValue).contains(.shouldResume) else { return }
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        try resume()
      } catch {
        print("Unable to resume the recording: \(error.localizedDescription)")
      }
    default: break
    }
  }
}
