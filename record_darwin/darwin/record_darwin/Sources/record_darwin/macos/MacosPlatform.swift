#if os(macOS)

import Foundation

// macOS: CoreAudio for inputs.
final class MacosPlatform: RecorderPlatform {
  private let macosDevices = MacosDeviceRegistry()
  private let macosEnvironment = MacosAudioEnvironment()

  var devices: DeviceRegistry { macosDevices }
  var environment: AudioEnvironment { macosEnvironment }
}

#endif
