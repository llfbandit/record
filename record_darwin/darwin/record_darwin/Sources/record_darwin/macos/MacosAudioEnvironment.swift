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

  // AVAudioEngine may go back to the system default input while it starts, whatever we set.
  // The tap then never fires, and nothing reports it.
  func verifyInput(_ device: Device?, config: RecordConfig, on node: AVAudioInputNode) throws {
    guard let uid = device?.id, let requested = CoreAudioDevices.id(forUid: uid) else { return }
    // The default input is what the engine reads anyway.
    guard requested != CoreAudioDevices.defaultInputId() else { return }

    let current = CoreAudioDevices.currentInputId(of: node)
    guard current != requested else { return }

    // Voice processing only works on the default input, and AVCaptureSession has no voice processing.
    if config.echoCancel || config.autoGain {
      throw RecorderError.startFailed(
        "Echo cancellation and auto gain need the system default input on macOS. "
          + "Choose the default input, or turn them off to record from this device.")
    }
    throw InputNotKept(
      reason: "requested input \(requested) but the engine reads \(current.map(String.init) ?? "an unknown input")")
  }
}

#endif
