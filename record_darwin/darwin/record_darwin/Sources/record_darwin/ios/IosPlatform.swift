#if os(iOS)

import AVFoundation

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

  // The route set the session's input. The engine captures from it.
  func openInput(
    on uid: String?,
    config: RecordConfig,
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
    onChange: @escaping () -> Void
  ) throws -> CaptureInput {
    try EngineInput.open(config: config, onBuffer: onBuffer, onChange: onChange)
  }
}

#endif
