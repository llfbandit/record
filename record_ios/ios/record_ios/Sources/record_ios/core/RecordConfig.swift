import Foundation

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

// An input the recorder can capture from.
public struct Device {
  let id: String
  let label: String
  let type: String
  // The sample rates the device announces, when the platform can tell them.
  let sampleRates: [Int]

  init(id: String, label: String, type: String = "unknown", sampleRates: [Int] = []) {
    self.id = id
    self.label = label
    self.type = type
    self.sampleRates = sampleRates
  }

  init?(map: [String: Any]) {
    guard let id = map["id"] as? String, let label = map["label"] as? String else { return nil }

    self.id = id
    self.label = label
    self.type = map["type"] as? String ?? "unknown"
    self.sampleRates = map["sampleRates"] as? [Int] ?? []
  }

  func toMap() -> [String: Any] {
    var map: [String: Any] = ["id": id, "label": label, "type": type]
    if !sampleRates.isEmpty { map["sampleRates"] = sampleRates }
    return map
  }
}

// What Dart asked for. The var fields are there for negotiated().
// We never change a config in place.
public struct RecordConfig {
  let encoder: String
  var bitRate: Int
  var sampleRate: Int
  var numChannels: Int
  let device: Device?
  let autoGain: Bool
  let echoCancel: Bool
  let noiseSuppress: Bool
  let audioInterruption: AudioInterruptionMode
  let streamBufferSize: Int?
  // The raw call arguments. Each platform reads its own keys here.
  let rawArgs: [String: Any]
}

extension RecordConfig {
  // Reads the Dart call arguments. A missing key keeps the default.
  static func fromMap(_ args: [String: Any]) throws -> RecordConfig {
    guard let encoder = args["encoder"] as? String else {
      throw RecorderError.error(message: "Call missing mandatory parameter encoder.", details: nil)
    }

    return RecordConfig(
      encoder: encoder,
      bitRate: args["bitRate"] as? Int ?? 128000,
      sampleRate: args["sampleRate"] as? Int ?? 44100,
      numChannels: args["numChannels"] as? Int ?? 2,
      device: (args["device"] as? [String: Any]).flatMap(Device.init(map:)),
      autoGain: args["autoGain"] as? Bool ?? false,
      echoCancel: args["echoCancel"] as? Bool ?? false,
      noiseSuppress: args["noiseSuppress"] as? Bool ?? false,
      audioInterruption: (args["audioInterruption"] as? Int)
        .flatMap(AudioInterruptionMode.init(rawValue:)) ?? .pause,
      streamBufferSize: args["streamBufferSize"] as? Int,
      rawArgs: args
    )
  }

  func toMap() -> [String: Any] {
    var map = rawArgs
    map["bitRate"] = bitRate
    map["sampleRate"] = sampleRate
    map["numChannels"] = numChannels
    return map
  }

  // Returns a new config with the negotiated values.
  func negotiated(sampleRate: Int, bitRate: Int, numChannels: Int) -> RecordConfig {
    var config = self
    config.sampleRate = sampleRate
    config.bitRate = bitRate
    config.numChannels = numChannels
    return config
  }

  // True when negotiation changed what the caller asked for.
  func isModified(from original: RecordConfig) -> Bool {
    bitRate != original.bitRate
      || sampleRate != original.sampleRate
      || numChannels != original.numChannels
  }
}
