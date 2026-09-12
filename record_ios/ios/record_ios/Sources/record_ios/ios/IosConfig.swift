import AVFoundation

// The `iosConfig` block of the Dart call arguments.
struct IosConfig {
  let categoryOptions: [AVAudioSession.CategoryOptions]
  let allowHapticsAndSystemSoundsDuringRecording: Bool

  init(map: [String: Any]) {
    let comps = map["categoryOptions"] as? String
    let options: [AVAudioSession.CategoryOptions]? = comps?.split(separator: ",").compactMap {
      IosConfig.avCategoryOption(from: String($0))
    }
    self.categoryOptions = options ?? []
    self.allowHapticsAndSystemSoundsDuringRecording = map["allowHapticsAndSystemSoundsDuringRecording"] as? Bool ?? false
  }

  static func avCategory(from string: String) -> AVAudioSession.Category {
    switch string {
    case "ambient": return .ambient
    case "playAndRecord": return .playAndRecord
    case "playback": return .playback
    case "record": return .record
    case "soloAmbient": return .soloAmbient
    default: return .playAndRecord
    }
  }

  static func avCategoryOptions(from strings: [String]) -> AVAudioSession.CategoryOptions {
    strings.reduce(into: AVAudioSession.CategoryOptions()) { result, s in
      if let opt = avCategoryOption(from: s) { result.insert(opt) }
    }
  }

  private static func avCategoryOption(from string: String) -> AVAudioSession.CategoryOptions? {
    switch string {
    case "mixWithOthers": return .mixWithOthers
    case "duckOthers": return .duckOthers
    case "interruptSpokenAudioAndMixWithOthers": return .interruptSpokenAudioAndMixWithOthers
    case "allowBluetooth":
      #if compiler(>=6.2)
      return .allowBluetoothHFP
      #else
      return .allowBluetooth
      #endif
    case "allowBluetoothA2DP": return .allowBluetoothA2DP
    case "allowAirPlay": return .allowAirPlay
    case "defaultToSpeaker": return .defaultToSpeaker
    case "overrideMutedMicrophoneInterruption":
      if #available(iOS 14.5, *) { return .overrideMutedMicrophoneInterruption }
      return nil
    default: return nil
    }
  }
}

extension RecordConfig {
  // The iOS keys that the shared config carries but never reads.
  var iosConfig: IosConfig {
    IosConfig(map: rawArgs["iosConfig"] as? [String: Any] ?? [:])
  }
}
