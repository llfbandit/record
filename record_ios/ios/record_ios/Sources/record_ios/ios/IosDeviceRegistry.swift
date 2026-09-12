import AVFoundation

// Lists the inputs AVAudioSession knows. It reads the current route.
final class IosDeviceRegistry: DeviceRegistry {
  func list() throws -> [Device] {
    try ports().map { port in
      Device(id: port.uid, label: port.portName, type: Self.type(of: port.portType))
    }
  }

  func inputChannelCount(for device: Device?) -> Int? {
    let count = AVAudioSession.sharedInstance().inputNumberOfChannels
    return count > 0 ? count : nil
  }

  func inputSampleRate(for device: Device?) -> Double? {
    let rate = AVAudioSession.sharedInstance().sampleRate
    return rate > 0 ? rate : nil
  }

  // The session must be able to record before it can list anything.
  func ports() throws -> [AVAudioSessionPortDescription] {
    let session = AVAudioSession.sharedInstance()

    let inputCapable: [AVAudioSession.Category] = [.record, .playAndRecord]
    if !inputCapable.contains(session.category) {
      do {
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
      } catch {
        throw RecorderError.error(
          message: "Failed to list inputs",
          details: "setCategory: \(error.localizedDescription)"
        )
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
