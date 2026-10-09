#if os(macOS)

import AVFoundation

// macOS: CoreAudio for inputs.
final class MacosPlatform: RecorderPlatform {
  private let macosDevices = MacosDeviceRegistry()
  private let macosEnvironment = MacosAudioEnvironment()

  var devices: DeviceRegistry { macosDevices }
  var environment: AudioEnvironment { macosEnvironment }

  // AVAudioEngine cannot hold a chosen input, so it only captures the default one.
  func makeEngine(
    config: RecordConfig,
    target: CaptureTarget,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine {
    if let uid = config.device?.id, let device = AVCaptureDevice(uniqueID: uid) {
      return CaptureSessionCapture(config: config, target: target, device: device, onEvent: onEvent)
    }
    return AudioEngineCapture(config: config, target: target, environment: environment, onEvent: onEvent)
  }
}

#endif
