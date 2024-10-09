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

public class RecordConfig {
  let encoder: String
  let bitRate: Int
  let sampleRate: Int
  let numChannels: Int
  let device: Device?
  let autoGain: Bool
  let echoCancel: Bool
  let noiseSuppress: Bool
  let iosConfig: IosConfig?

  init(encoder: String,
       bitRate: Int,
       sampleRate: Int,
       numChannels: Int,
       device: Device? = nil,
       autoGain: Bool = false,
       echoCancel: Bool = false,
       noiseSuppress: Bool = false,
       iosConfig: IosConfig? = nil
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

#if os(iOS)
struct IosConfig {
  let categoryOptions: [AVAudioSession.CategoryOptions]
  let manageAudioSession: Bool

  init(map: [String: Any]) {
    let comps = map["categoryOptions"] as? String
    let options: [AVAudioSession.CategoryOptions]? = comps?.split(separator: ",").compactMap {
      switch $0 {
      case "mixWithOthers":
          .mixWithOthers
      case "duckOthers":
          .duckOthers
      case "allowBluetooth":
          .allowBluetooth
      case "defaultToSpeaker":
          .defaultToSpeaker
      case "interruptSpokenAudioAndMixWithOthers":
          .interruptSpokenAudioAndMixWithOthers
      case "allowBluetoothA2DP":
          .allowBluetoothA2DP
      case "allowAirPlay":
          .allowAirPlay
      case "overrideMutedMicrophoneInterruption":
        if #available(iOS 14.5, *) { .overrideMutedMicrophoneInterruption } else { nil }
      default: nil
      }
    }
    self.categoryOptions = options ?? []
    self.manageAudioSession = map["manageAudioSession"] as? Bool ?? true
  }
}
#else
struct IosConfig {
  init(map: [String: Any]) {}
}
#endif