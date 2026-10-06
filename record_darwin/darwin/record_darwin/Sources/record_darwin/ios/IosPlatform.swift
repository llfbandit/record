#if os(iOS)

import Foundation

// iOS: AVAudioSession for state and inputs.
final class IosPlatform: RecorderPlatform {
  let iosEnvironment = IosAudioEnvironment()
  let devices: DeviceRegistry
  let inputRoute: InputRoute

  var environment: AudioEnvironment { iosEnvironment }

  init() {
    let devices = IosDeviceRegistry()
    self.devices = devices
    inputRoute = IosInputRoute(devices: devices)
  }
}

#endif
