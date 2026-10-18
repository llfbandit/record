#if os(iOS)

import AVFoundation

// Lists the inputs AVAudioSession knows.
final class IosDeviceRegistry: DeviceRegistry {
  func list() throws -> [Device] {
    try ports().map { port in
      Device(id: port.uid, label: port.portName, type: Self.type(of: port.portType))
    }
  }

  // Never changes the category: during a pause, the app may use its own to play.
  func isAvailable(_ deviceId: String) -> Bool {
    let session = AVAudioSession.sharedInstance()
    // Without a record category, the list is not complete.
    guard Self.canRecord(session), let inputs = session.availableInputs else { return true }
    return inputs.contains { $0.uid == deviceId }
  }

  // The engine does not always tell: during a pause, or when the route moves but the engine runs on.
  func watch(_ onChange: @escaping () -> Void) -> () -> Void {
    let observer = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: nil
    ) { notification in
      guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
            reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
      onChange()
    }
    return { NotificationCenter.default.removeObserver(observer) }
  }

  // The session must be able to record before it can list anything.
  func ports() throws -> [AVAudioSessionPortDescription] {
    let session = AVAudioSession.sharedInstance()

    if !Self.canRecord(session) {
      try RecorderError.wrapping("setCategory", failure: "Failed to list inputs") {
        try session.setCategory(.playAndRecord, options: IosConfig.avCategoryOptions(from: ["defaultToSpeaker", "allowBluetooth"]))
      }
    }

    return session.availableInputs ?? []
  }

  private static func canRecord(_ session: AVAudioSession) -> Bool {
    session.category == .record || session.category == .playAndRecord
  }

  private static func type(of portType: AVAudioSession.Port) -> String {
    if portType == .builtInMic    { return "builtIn" }
    if portType == .headsetMic    { return "wiredHeadset" }
    if portType == .lineIn        { return "lineIn" }
    if portType == .bluetoothHFP  { return "bluetoothSco" }
    if portType == .bluetoothA2DP { return "bluetoothA2dp" }
    if portType == .bluetoothLE   { return "bluetoothLe" }
    if portType == .usbAudio      { return "usb" }
    if portType == .HDMI          { return "hdmi" }
    if portType == .airPlay       { return "airPlay" }
    if #available(iOS 14.0, *) {
      if portType == .thunderbolt { return "thunderbolt" }
    }
    return "unknown"
  }
}

#endif
