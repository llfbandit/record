#if os(macOS)

import AVFoundation

// macOS: CoreAudio for inputs.
final class MacosPlatform: RecorderPlatform {
  let devices: DeviceRegistry = MacosDeviceRegistry()
  let environment: AudioEnvironment = MacosAudioEnvironment()
  let inputRoute: InputRoute = MacosInputRoute()

  // A HAL unit stays on its input. AVAudioEngine can leave it: see HalInput.
  func openInput(
    on uid: String?,
    config: RecordConfig,
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
    onChange: @escaping () -> Void
  ) throws -> CaptureInput {
    try HalInput.open(on: uid, config: config, onBuffer: onBuffer, onChange: onChange)
  }
}

#endif
