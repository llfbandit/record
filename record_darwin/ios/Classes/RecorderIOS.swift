import AVFoundation

func listInputs() throws -> [Device] {
  var devices: [Device] = []

  try listInputDevices()?.forEach { input in
    devices.append(Device(id: input.uid, label: input.portName))
  }

  return devices
}

func listInputDevices() throws -> [AVAudioSessionPortDescription]? {
  let audioSession = AVAudioSession.sharedInstance()
  let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth]
  
  do {
    try audioSession.setCategory(.playAndRecord, options: options)
  } catch {
    throw RecorderError.error(message: "Failed to list inputs", details: "setCategory: \(error.localizedDescription)")
  }

  return audioSession.availableInputs
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

extension AudioRecordingDelegate {
  func initAVAudioSession(config: RecordConfig) throws {
    let audioSession = AVAudioSession.sharedInstance()
    let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth]
    
    do {
      try audioSession.setCategory(.playAndRecord, options: options)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setCategory: \(error.localizedDescription)")
    }
    
    do {
      try audioSession.setPreferredSampleRate((config.sampleRate <= 48000) ? Double(config.sampleRate) : 48000.0)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setPreferredSampleRate: \(error.localizedDescription)")
    }
    
    do {
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation) // Must be done before setting channels and others
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setActive: \(error.localizedDescription)")
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
    
    if type == AVAudioSession.InterruptionType.began {
      pause()
    } else if type == AVAudioSession.InterruptionType.ended {
      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
      
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      
      if options.contains(.shouldResume) {
        do {
          try resume()
        } catch {
          stop(completionHandler: {(path) -> () in })
        }
      } else {
        stop(completionHandler: {(path) -> () in })
      }
    }
  }
}
