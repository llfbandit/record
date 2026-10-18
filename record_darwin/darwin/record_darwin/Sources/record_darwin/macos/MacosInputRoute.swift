#if os(macOS)

import Foundation

// Finds the CoreAudio input. HalInput opens its unit on it.
final class MacosInputRoute: InputRoute {
  // The default input is bound by its UID too: a rebuild comes back to it, and its loss is seen.
  func bind(_ deviceId: String?, channels: Int) throws -> String? {
    let device = if let deviceId { CoreAudioDevices.id(forUid: deviceId) } else { CoreAudioDevices.defaultInputId() }
    guard let device else { throw RecorderError.noInputDevice }
    // Without a UID, the raw id works too.
    return CoreAudioDevices.deviceUid(of: device) ?? String(device)
  }

  // A HAL unit stays on its device.
  func captures(from uid: String) -> Bool? { nil }

  // Nothing stays on the system.
  func release() {}
}

#endif
