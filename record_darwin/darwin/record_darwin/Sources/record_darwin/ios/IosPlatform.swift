#if os(iOS)

import Foundation

// iOS: AVAudioSession for state and inputs.
final class IosPlatform: RecorderPlatform {
  let iosDevices: IosDeviceRegistry
  let iosEnvironment: IosAudioEnvironment

  var devices: DeviceRegistry { iosDevices }
  var environment: AudioEnvironment { iosEnvironment }

  init() {
    let devices = IosDeviceRegistry()
    iosDevices = devices
    iosEnvironment = IosAudioEnvironment(devices: devices)
  }
}

#endif
