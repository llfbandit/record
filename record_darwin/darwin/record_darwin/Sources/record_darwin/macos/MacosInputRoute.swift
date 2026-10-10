#if os(macOS)

import AVFoundation

// Sets the CoreAudio device of the engine's input unit.
final class MacosInputRoute: InputRoute {
  // macOS has no channel preference to set.
  func bind(_ deviceId: String?, channels: Int, to engine: AVAudioEngine) throws -> String? {
    // The engine follows the system default, so we cannot name it.
    guard let deviceId else { return nil }
    guard let target = CoreAudioDevices.id(forUid: deviceId) else { throw RecorderError.noInputDevice }

    try RecorderError.wrapping("setDeviceID(\(deviceId))") {
      try engine.inputNode.auAudioUnit.setDeviceID(target)
    }
    return CoreAudioDevices.deviceUid(of: target)
  }

  func captures(from uid: String, engine: AVAudioEngine) -> Bool? {
    // With voice processing, the unit gives the output device. So we cannot tell.
    guard !engine.inputNode.isVoiceProcessingEnabled else { return nil }
    // The engine can wrap the input and the output in its own aggregate device (e.g. with Bluetooth buds).
    // Then the input is one of the devices inside.
    let uids = CoreAudioDevices.uids(of: engine.inputNode.auAudioUnit.deviceID)
    return uids.isEmpty ? nil : uids.contains(uid)
  }

  // The device is set on each engine only, so nothing stays on the system.
  func release() {}
}

#endif
