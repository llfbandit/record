import AVFoundation

extension Recorder {
#if os(iOS)
  func initAVAudioSession(config: RecordConfig) throws {
    let audioSession = AVAudioSession.sharedInstance()
    let options: AVAudioSession.CategoryOptions = [.allowBluetooth]
    
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
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation) // Must be done before setting channels & buffer duration
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setActive: \(error.localizedDescription)")
    }
    
    do {
      try audioSession.setPreferredInputNumberOfChannels(
        (config.numChannels > audioSession.inputNumberOfChannels) ? audioSession.inputNumberOfChannels : max(1, config.numChannels)
      )
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "setPreferredInputNumberOfChannels: \(error.localizedDescription)")
    }
    
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: nil,
      using: onAudioSessionInterruption)
  }

  func onAudioSessionInterruption(notification: Notification) -> Void {
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
          resume()
        } else {
          stop(completionHandler: {(path) -> () in })
        }
      }
    }
#endif
}
