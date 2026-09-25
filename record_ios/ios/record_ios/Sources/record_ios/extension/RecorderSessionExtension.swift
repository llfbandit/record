import AVFoundation

extension AudioRecordingDelegate {
  @discardableResult
  func initAVAudioSession(config: RecordConfig, manageAudioSession: Bool, queue: DispatchQueue) throws -> NSObjectProtocol {
    let session = AVAudioSession.sharedInstance()

    try applyPreferredSampleRate(config.sampleRate, session: session)
    try applyInterruptionPreference(suppressAlerts: config.audioInterruption != AudioInterruptionMode.pause, session: session)

    if manageAudioSession {
      try applyCategory(AVAudioSession.CategoryOptions(config.iosConfig.categoryOptions), session: session)
      try activateSession(session)
    }

    try applyHapticsPreference(config.iosConfig.allowHapticsAndSystemSoundsDuringRecording, session: session)
    try applyPreferredChannelCount(config.numChannels, session: session)
    try applyPreferredInputDevice(config.device)

    return registerInterruptionObserver(queue: queue)
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
        pauseForInterruption()
      }
    case .ended:
      // The system's shouldResume hint is intended for playback; resume only recordings this delegate paused.
      guard config.audioInterruption == AudioInterruptionMode.pauseResume,
            shouldResumeAfterInterruption else { return }
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
