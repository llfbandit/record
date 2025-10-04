import AVFoundation

public enum AudioEncoder: String {
  case aacLc = "aacLc"
  case aacEld = "aacEld"
  case aacHe = "aacHe"
  case amrNb = "amrNb"
  case amrWb = "amrWb"
  case opus = "opus"
  case flac = "flac"
  case pcm16bits = "pcm16bits"
  case wav = "wav"
}

public enum AudioInterruptionMode: Int {
  case none = 0
  case pause = 1
  case pauseResume = 2
}

public class RecordConfig {
  let encoder: String
  let bitRate: Int
  let sampleRate: Int
  let numChannels: Int
  let device: Device?
  let autoGain: Bool
  let echoCancel: Bool
  let noiseSuppress: Bool
  let iosConfig: IosConfig
  let audioInterruption: AudioInterruptionMode
  let streamBufferSize: Int?

  init(encoder: String,
       bitRate: Int,
       sampleRate: Int,
       numChannels: Int,
       device: Device? = nil,
       autoGain: Bool = false,
       echoCancel: Bool = false,
       noiseSuppress: Bool = false,
       iosConfig: IosConfig,
       audioInterruption: AudioInterruptionMode = AudioInterruptionMode.pause,
       streamBufferSize: Int?
  ) {
    self.encoder = encoder
    self.bitRate = bitRate
    self.sampleRate = sampleRate
    self.numChannels = numChannels
    self.device = device
    self.autoGain = autoGain
    self.echoCancel = echoCancel
    self.noiseSuppress = noiseSuppress
    self.iosConfig = iosConfig
    self.audioInterruption = audioInterruption
    self.streamBufferSize = streamBufferSize
  }
}

public class Device {
  let id: String
  let label: String

  init(id: String, label: String) {
    self.id = id
    self.label = label
  }

  init(map: [String: Any]) {
    self.id = map["id"] as! String
    self.label = map["label"] as! String
  }

  func toMap() -> [String: Any] {
    return [
      "id": id,
      "label": label
    ]
  }
}

struct IosConfig {
  let categoryOptions: [AVAudioSession.CategoryOptions]
  let manageAudioSession: Bool

  init(map: [String: Any]) {
    let comps = map["categoryOptions"] as? String
    let options: [AVAudioSession.CategoryOptions]? = comps?.split(separator: ",").compactMap {
      switch $0 {
      case "mixWithOthers":
        AVAudioSession.CategoryOptions.mixWithOthers
      case "duckOthers":
        AVAudioSession.CategoryOptions.duckOthers
      case "allowBluetooth":
        #if compiler(>=6.2)
        // For XCode 26.0+, Swift 6.2 version
        AVAudioSession.CategoryOptions.allowBluetoothHFP
        #else
        // Deprecated in 26.0, not 8.0. Thanks Apple!
        AVAudioSession.CategoryOptions.allowBluetooth
        #endif
      case "defaultToSpeaker":
        AVAudioSession.CategoryOptions.defaultToSpeaker
      case "interruptSpokenAudioAndMixWithOthers":
        AVAudioSession.CategoryOptions.interruptSpokenAudioAndMixWithOthers
      case "allowBluetoothA2DP":
        AVAudioSession.CategoryOptions.allowBluetoothA2DP
      case "allowAirPlay":
        AVAudioSession.CategoryOptions.allowAirPlay
      case "overrideMutedMicrophoneInterruption":
        if #available(iOS 14.5, *) { AVAudioSession.CategoryOptions.overrideMutedMicrophoneInterruption } else { nil }
      default: nil
      }
    }
    self.categoryOptions = options ?? []
    self.manageAudioSession = map["manageAudioSession"] as? Bool ?? true
  }
}
