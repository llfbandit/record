#if os(macOS)

import AVFoundation

// macOS has no audio session and sends no interruption.
// So the environment only picks the input device.
final class MacosAudioEnvironment: AudioEnvironment {
  // macOS never sends an event, so the handler is dropped.
  func bind(onEvent: @escaping (EnvironmentEvent) -> Void) {}

  func prepare(_ config: RecordConfig) throws {}

  func activate() throws {}

  func release() {}

  func bindInput(_ device: Device?, to node: AVAudioInputNode) throws {
    // No device, or CoreAudio does not know it. We keep the default input.
    guard let uid = device?.id, let deviceId = CoreAudioDevices.id(forUid: uid) else { return }

    try RecorderError.wrapping("setDeviceID(\(uid))") {
      try node.auAudioUnit.setDeviceID(deviceId)
    }
  }
}

#endif
