import Foundation

@testable import record_darwin

// A config with sane defaults, so a test only names what it cares about.
func makeConfig(
  encoder: String = "aacLc",
  bitRate: Int = 128000,
  sampleRate: Int = 44100,
  numChannels: Int = 2,
  device: Device? = nil,
  audioInterruption: AudioInterruptionMode = .pause,
  streamBufferSize: Int? = nil,
  extra: [String: Any] = [:]
) -> RecordConfig {
  var args: [String: Any] = [
    "encoder": encoder,
    "bitRate": bitRate,
    "sampleRate": sampleRate,
    "numChannels": numChannels,
    "audioInterruption": audioInterruption.rawValue,
  ]
  if let device { args["device"] = device.toMap() }
  if let streamBufferSize { args["streamBufferSize"] = streamBufferSize }
  args.merge(extra) { _, new in new }

  return try! RecordConfig.fromMap(args)
}
