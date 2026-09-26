#if os(iOS)

import AVFoundation

// Lists the inputs AVAudioSession knows.
final class IosDeviceRegistry: DeviceRegistry {
  func list() throws -> [Device] {
    try ports().map { port in
      Device(id: port.uid, label: port.portName, type: Self.type(of: port.portType))
    }
  }

  func isAvailable(_ device: Device) -> Bool {
    // We cannot list the inputs, so we keep what was asked.
    guard let ports = try? ports() else { return true }
    return ports.contains { $0.uid == device.id }
  }

  // The session must be able to record before it can list anything.
  func ports() throws -> [AVAudioSessionPortDescription] {
    let session = AVAudioSession.sharedInstance()

    let inputCapable: [AVAudioSession.Category] = [.record, .playAndRecord]
    if !inputCapable.contains(session.category) {
      try RecorderError.wrapping("setCategory", failure: "Failed to list inputs") {
        try session.setCategory(.playAndRecord, options: IosConfig.avCategoryOptions(from: ["defaultToSpeaker", "allowBluetooth"]))
      }
    }

    return session.availableInputs ?? []
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
