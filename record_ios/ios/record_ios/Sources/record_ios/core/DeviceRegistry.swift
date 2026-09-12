import Foundation

// What the recorder needs to know about the input hardware.
protocol DeviceRegistry {
  func list() throws -> [Device]

  // What the hardware gives us, to negotiate the format. Nil if the platform cannot tell.
  func inputChannelCount(for device: Device?) -> Int?
  func inputSampleRate(for device: Device?) -> Double?
}
