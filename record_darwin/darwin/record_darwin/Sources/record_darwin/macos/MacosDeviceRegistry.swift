#if os(macOS)

import AVFoundation

// Lists the inputs CoreAudio knows.
final class MacosDeviceRegistry: DeviceRegistry {
  func list() throws -> [Device] {
    CoreAudioDevices.captureDevices().map { input in
      let deviceId = CoreAudioDevices.id(forUid: input.uniqueID)

      return Device(
        id: input.uniqueID,
        label: input.localizedName,
        type: deviceId.map { CoreAudioDevices.transportType(of: $0) } ?? "unknown",
        sampleRates: deviceId.map { CoreAudioDevices.sampleRates(of: $0) } ?? []
      )
    }
  }

  // Takes a UID or a raw device id, like bindInput does.
  func isAvailable(_ device: Device) -> Bool {
    CoreAudioDevices.id(forUid: device.id) != nil
  }
}

#endif
