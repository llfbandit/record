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

  func bind(_ deviceId: String?, channels: Int) throws -> String? {
    let session = AVAudioSession.sharedInstance()

    // Input first. It changes the route, and the channel limit depends on the route.
    let port = try deviceId.map { deviceId in
      guard let port = try m_devices.ports().first(where: { $0.uid == deviceId }) else {
        throw RecorderError.noInputDevice
      }
      return port
    }
    if let port {
      // Each session call is a round trip to the audio server, so we skip the ones that change nothing.
      if session.preferredInput?.uid != port.uid {
        try RecorderError.wrapping("setPreferredInput") { try session.setPreferredInput(port) }
      }
      m_preferredInputUid = port.uid
    } else {
      // Else a device we left would take the route back when it returns.
      release()
    }

    let channels = min(channels, session.maximumInputNumberOfChannels)
    if channels > 0 && channels != session.preferredInputNumberOfChannels {
      try RecorderError.wrapping("setPreferredInputNumberOfChannels") {
        try session.setPreferredInputNumberOfChannels(channels)
      }
    }
    return port?.uid ?? Self.currentUid()
  }

  func captures(from uid: String) -> Bool? {
    Self.currentUid().map { $0 == uid }
  }

  // Only if it is still ours. The app may have changed it since.
  func release() {
    guard let uid = m_preferredInputUid else { return }
    m_preferredInputUid = nil

    let session = AVAudioSession.sharedInstance()
    if session.preferredInput?.uid == uid { try? session.setPreferredInput(nil) }
  }

  // MARK: - Private

  private static func currentUid() -> String? {
    AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid
  }
}

#endif
