#if os(iOS)

import AVFoundation

// Sets the session's preferred input. The engine then captures from it.
final class IosInputRoute: InputRoute {
  private let m_devices: IosDeviceRegistry
  // The input we chose for this take. release() clears it.
  private var m_preferredInputUid: String?

  init(devices: IosDeviceRegistry) {
    m_devices = devices
  }

  deinit {
    release()
  }

  func bind(_ deviceId: String?, channels: Int, to engine: AVAudioEngine) throws {
    let session = AVAudioSession.sharedInstance()

    // Input first. It changes the route, and the channel limit depends on the route.
    let port = try deviceId.flatMap { deviceId in
      try m_devices.ports().first { $0.uid == deviceId }
    }
    if let port {
      try RecorderError.wrapping("setPreferredInput") { try session.setPreferredInput(port) }
      m_preferredInputUid = port.uid
    }

    let channels = min(channels, session.maximumInputNumberOfChannels)
    if channels > 0 {
      try RecorderError.wrapping("setPreferredInputNumberOfChannels") {
        try session.setPreferredInputNumberOfChannels(channels)
      }
    }
  }

  // Only if it is still ours. The app may have changed it since.
  func release() {
    guard let uid = m_preferredInputUid else { return }
    m_preferredInputUid = nil

    let session = AVAudioSession.sharedInstance()
    if session.preferredInput?.uid == uid { try? session.setPreferredInput(nil) }
  }
}

#endif
