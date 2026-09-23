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
  var bitRate: Int
  var sampleRate: Int
  var numChannels: Int
  let device: Device?
  let autoGain: Bool
  let echoCancel: Bool
  let noiseSuppress: Bool
  let iosConfig: IosConfig
  let audioInterruption: AudioInterruptionMode
  let streamBufferSize: Int?

  private var m_args: [String: Any] = [:]

  var isModified: Bool {
    bitRate    != (m_args["bitRate"]     as? Int ?? 128000) ||
    sampleRate != (m_args["sampleRate"]  as? Int ?? 44100)  ||
    numChannels != (m_args["numChannels"] as? Int ?? 2)
  }

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
  let type: String

  init(id: String, label: String, type: String = "unknown") {
    self.id = id
    self.label = label
    self.type = type
  }

  init(map: [String: Any]) {
    self.id = map["id"] as! String
    self.label = map["label"] as! String
    self.type = map["type"] as? String ?? "unknown"
  }

  func toMap() -> [String: Any] {
    return ["id": id, "label": label, "type": type]
  }
}

struct IosConfig {
  let categoryOptions: [AVAudioSession.CategoryOptions]
  let allowHapticsAndSystemSoundsDuringRecording: Bool
  let restartOnEngineConfigurationChange: Bool

  init(map: [String: Any]) {
    let comps = map["categoryOptions"] as? String
    let options: [AVAudioSession.CategoryOptions]? = comps?.split(separator: ",").compactMap {
      IosConfig.avCategoryOption(from: String($0))
    }
    self.categoryOptions = options ?? []
    self.allowHapticsAndSystemSoundsDuringRecording = map["allowHapticsAndSystemSoundsDuringRecording"] as? Bool ?? false
    self.restartOnEngineConfigurationChange = map["restartOnEngineConfigurationChange"] as? Bool ?? false
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
  func toMap() -> [String: Any] {
    var map = m_args
    map["bitRate"] = bitRate
    map["sampleRate"] = sampleRate
    map["numChannels"] = numChannels
    return map
  }

  static func fromMap(_ args: [String: Any]) throws -> RecordConfig {
    guard let encoder = args["encoder"] as? String else {
      throw RecorderError.error(message: "Call missing mandatory parameter encoder.", details: nil)
    }
    let device = (args["device"] as? [String: Any]).map(Device.init(map:))
    let iosConfig = (args["iosConfig"] as? [String: Any]).map(IosConfig.init(map:)) ?? IosConfig(map: [:])
    let audioInterruption = (args["audioInterruption"] as? Int)
      .flatMap(AudioInterruptionMode.init(rawValue:)) ?? .pause
    let config = RecordConfig(
      encoder: encoder,
      bitRate: args["bitRate"] as? Int ?? 128000,
      sampleRate: args["sampleRate"] as? Int ?? 44100,
      numChannels: args["numChannels"] as? Int ?? 2,
      device: device,
      autoGain: args["autoGain"] as? Bool ?? false,
      echoCancel: args["echoCancel"] as? Bool ?? false,
      noiseSuppress: args["noiseSuppress"] as? Bool ?? false,
      iosConfig: iosConfig,
      audioInterruption: audioInterruption,
      streamBufferSize: args["streamBufferSize"] as? Int
    )
    config.m_args = args
    return config
  }
}
