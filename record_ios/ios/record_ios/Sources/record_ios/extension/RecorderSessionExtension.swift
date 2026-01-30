import AVFoundation

extension AudioRecordingDelegate {
  func initAVAudioSession(config: RecordConfig, manageAudioSession: Bool) throws {
    let manage = manageAudioSession && config.iosConfig.manageAudioSession

    let audioSession = AVAudioSession.sharedInstance()
    
    do {
      try audioSession.setPreferredSampleRate((config.sampleRate <= 48000) ? Double(config.sampleRate) : 48000.0)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setPreferredSampleRate: \(error.localizedDescription)")
    }
    
    if #available(iOS 14.5, *) {
      do {
        try audioSession.setPrefersNoInterruptionsFromSystemAlerts(config.audioInterruption == AudioInterruptionMode.none)
      } catch {
        throw RecorderError.error(message: "Failed to start recording", details: "setPrefersNoInterruptionsFromSystemAlerts: \(error.localizedDescription)")
      }
    }
    
    if manage {
      do {
          try audioSession.setCategory(.playAndRecord, options: AVAudioSession.CategoryOptions(config.iosConfig.categoryOptions))
      } catch {
        throw RecorderError.error(message: "Failed to start recording", details: "setCategory: \(error.localizedDescription)")
      }

      do {
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation) // Must be done before setting channels and others
      } catch {
        throw RecorderError.error(message: "Failed to start recording", details: "setActive: \(error.localizedDescription)")
      }
    }
    
    do {
      let newPreferredInputNumberOfChannels = min(config.numChannels, audioSession.maximumInputNumberOfChannels)

      if newPreferredInputNumberOfChannels > 0 {
        try audioSession.setPreferredInputNumberOfChannels(newPreferredInputNumberOfChannels)
      }
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setPreferredInputNumberOfChannels: \(error.localizedDescription)")
    }
    
    do {
      try setInput(config)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setInput: \(error.localizedDescription)")
    }
    
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: nil,
      using: onAudioSessionInterruption)
  }

  private func onAudioSessionInterruption(notification: Notification) -> Void {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }
    
    guard let config = self.config else {
      return
    }
  
    if type == AVAudioSession.InterruptionType.began {
      if config.audioInterruption != AudioInterruptionMode.none {
        pause()
      }
    } else if type == AVAudioSession.InterruptionType.ended {
      if config.audioInterruption == AudioInterruptionMode.pauseResume {
        do {
          try AVAudioSession.sharedInstance().setActive(true)
          try resume()
        } catch {
          stop { path in }
        }
      }
    }
  }

  private func setInput(_ config: RecordConfig) throws {
    guard let device = config.device else {
      return
    }
    
    let inputs = try listInputDevices()
    guard let inputs = inputs else {
      return
    }
    
    let audioSession = AVAudioSession.sharedInstance()
    
    for input in inputs {
      if input.uid == device.id {
        try audioSession.setPreferredInput(input)
        break
      }
    }
  }
}
