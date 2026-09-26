#if os(macOS)

import AVFoundation

// Reads the audio inputs from CoreAudio and AVCaptureDevice.
enum CoreAudioDevices {
  static func captureDevices() -> [AVCaptureDevice] {
    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInMicrophone, .externalUnknown]

    if #available(macOS 14.0, *) {
      deviceTypes.append(.microphone)
    }

    return AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .audio,
      position: .unspecified
    ).devices
  }

  // Matches the device UID, or a raw device id.
  static func id(forUid uid: String) -> AudioDeviceID? {
    // A raw id is only valid while its device exists.
    if let rawId = AudioDeviceID(uid), deviceUid(of: rawId) != nil { return rawId }

    var addr = address(kAudioHardwarePropertyTranslateUIDToDevice)
    var cfUid = uid as CFString
    var deviceId = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = withUnsafePointer(to: &cfUid) {
      AudioObjectGetPropertyData(systemObject, &addr, UInt32(MemoryLayout<CFString>.size), $0, &size, &deviceId)
    }
    return status == noErr && deviceId != kAudioObjectUnknown ? deviceId : nil
  }

  // The UID CoreAudio gives this device.
  static func deviceUid(of deviceId: AudioDeviceID) -> String? {
    let uid: Unmanaged<CFString>?? = property(kAudioDevicePropertyDeviceUID, of: deviceId, initial: nil)
    return uid??.takeRetainedValue() as String?
  }

  static func transportType(of deviceId: AudioDeviceID) -> String {
    switch property(kAudioDevicePropertyTransportType, of: deviceId, initial: UInt32(0)) ?? 0 {
    case kAudioDeviceTransportTypeBuiltIn:     return "builtIn"
    case kAudioDeviceTransportTypeUSB:         return "usb"
    case kAudioDeviceTransportTypeBluetooth:   return "bluetoothSco"
    case kAudioDeviceTransportTypeBluetoothLE: return "bluetoothLe"
    case kAudioDeviceTransportTypeHDMI:        return "hdmi"
    case kAudioDeviceTransportTypeDisplayPort: return "displayPort"
    case kAudioDeviceTransportTypeAirPlay:     return "airPlay"
    case kAudioDeviceTransportTypeThunderbolt: return "thunderbolt"
    default:                                   return "unknown"
    }
  }

  static func sampleRates(of deviceId: AudioDeviceID) -> [Int] {
    let ranges = properties(kAudioDevicePropertyAvailableNominalSampleRates, of: deviceId, initial: AudioValueRange())

    var rates = Set<Int>()
    for range in ranges {
      rates.insert(Int(range.mMinimum))
      if range.mMinimum != range.mMaximum { rates.insert(Int(range.mMaximum)) }
    }
    return rates.sorted()
  }

  // MARK: - Private

  private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

  private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  }

  // Reads one fixed-size value. Nil if CoreAudio fails.
  private static func property<T>(
    _ selector: AudioObjectPropertySelector,
    of objectId: AudioObjectID,
    initial: T
  ) -> T? {
    var addr = address(selector)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutableBytes(of: &value) {
      AudioObjectGetPropertyData(objectId, &addr, 0, nil, &size, $0.baseAddress!)
    }
    return status == noErr ? value : nil
  }

  // Reads a list of values. Empty if CoreAudio fails.
  private static func properties<T>(
    _ selector: AudioObjectPropertySelector,
    of objectId: AudioObjectID,
    initial: T
  ) -> [T] {
    var addr = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(objectId, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }

    let count = Int(size) / MemoryLayout<T>.size
    guard count > 0 else { return [] }

    var values = [T](repeating: initial, count: count)
    let status = values.withUnsafeMutableBytes {
      AudioObjectGetPropertyData(objectId, &addr, 0, nil, &size, $0.baseAddress!)
    }
    return status == noErr ? values : []
  }
}

#endif
