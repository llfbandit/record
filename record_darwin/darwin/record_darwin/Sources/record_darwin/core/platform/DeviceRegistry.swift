import Foundation

// What the recorder needs to know about the input hardware.
protocol DeviceRegistry {
  func list() throws -> [Device]

  // False when the device is gone. When unsure, true.
  func isAvailable(_ deviceId: String) -> Bool
}

extension DeviceRegistry {
  // The device if it is still there, else nil: the default input.
  func available(_ device: Device?) -> Device? {
    device.flatMap { isAvailable($0.id) ? $0 : nil }
  }
}
