#if os(macOS)

import Foundation

// macOS: CoreAudio for inputs.
final class MacosPlatform: RecorderPlatform {
  let devices: DeviceRegistry = MacosDeviceRegistry()
  let environment: AudioEnvironment = MacosAudioEnvironment()
  let inputRoute: InputRoute = MacosInputRoute()
}

#endif
