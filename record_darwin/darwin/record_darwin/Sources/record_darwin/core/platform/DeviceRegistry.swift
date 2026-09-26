import Foundation

// What the recorder needs to know about the input hardware.
protocol DeviceRegistry {
  func list() throws -> [Device]

  // False when the device is gone. When unsure, true.
  func isAvailable(_ device: Device) -> Bool
}
