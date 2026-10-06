#if os(macOS)

import AVFoundation

// Sets the CoreAudio device of the engine's input unit.
final class MacosInputRoute: InputRoute {
  // macOS has no channel preference to set.
  func bind(_ deviceId: String?, channels: Int, to engine: AVAudioEngine) throws {
    // No device, or CoreAudio does not know it. We keep the default input.
    guard let deviceId, let target = CoreAudioDevices.id(forUid: deviceId) else { return }

    try RecorderError.wrapping("setDeviceID(\(deviceId))") {
      try engine.inputNode.auAudioUnit.setDeviceID(target)
    }
  }

  // The device is set on each engine only, so nothing stays on the system.
  func release() {}
}

#endif
