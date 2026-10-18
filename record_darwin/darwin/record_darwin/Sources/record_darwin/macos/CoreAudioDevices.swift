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
    ).devices.filter { input in
      // AVCaptureDevice still lists a device for a moment after it goes.
      guard let deviceId = id(forUid: input.uniqueID) else { return false }
      // A private aggregate belongs to the code that made it, e.g. the one voice processing makes.
      return !isPrivateAggregate(deviceId)
    }
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

  // The input the system uses now. Nil if there is none.
  static func defaultInputId() -> AudioDeviceID? {
    if let deviceId = property(kAudioHardwarePropertyDefaultInputDevice, of: systemObject, initial: AudioDeviceID(kAudioObjectUnknown)),
       deviceId != kAudioObjectUnknown, deviceUid(of: deviceId) != nil {
      return deviceId
    }

    // Right after the default input goes, the system can still name it. Then any other input does.
    return captureDevices().first.flatMap { id(forUid: $0.uniqueID) }
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

  // The rate the device runs at. Nil if CoreAudio fails.
  static func sampleRate(of deviceId: AudioDeviceID) -> Double? {
    property(kAudioDevicePropertyNominalSampleRate, of: deviceId, initial: Float64(0))
  }

  // The most frames the device can give in one render. Nil if CoreAudio fails.
  static func maxBufferFrames(of deviceId: AudioDeviceID) -> UInt32? {
    property(kAudioDevicePropertyBufferFrameSizeRange, of: deviceId, initial: AudioValueRange()).map { UInt32($0.mMaximum) }
  }

  // The channels the device captures. 0 if it has none, or if CoreAudio fails.
  static func inputChannels(of deviceId: AudioDeviceID) -> Int {
    var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceId, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }

    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(deviceId, &addr, 0, nil, &size, raw) == noErr else { return 0 }

    let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
  }

  // Calls onChange, on another thread, when a device comes or goes. Returns what stops it.
  static func watchDevices(_ onChange: @escaping () -> Void) -> () -> Void {
    watch(kAudioHardwarePropertyDevices, of: systemObject, onChange)
  }

  // Calls onChange, on another thread, when this property of the object changes. Returns what stops it.
  static func watch(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    of objectId: AudioObjectID,
    _ onChange: @escaping () -> Void
  ) -> () -> Void {
    var addr = address(selector, scope: scope)
    let queue = DispatchQueue.global(qos: .userInitiated)
    let listener: AudioObjectPropertyListenerBlock = { _, _ in onChange() }

    guard AudioObjectAddPropertyListenerBlock(objectId, &addr, queue, listener) == noErr else { return {} }
    return {
      var addr = address(selector, scope: scope)
      AudioObjectRemovePropertyListenerBlock(objectId, &addr, queue, listener)
    }
  }

  // MARK: - Private

  private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

  private static func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  private static func isPrivateAggregate(_ deviceId: AudioDeviceID) -> Bool {
    let composition: Unmanaged<CFDictionary>?? = property(kAudioAggregateDevicePropertyComposition, of: deviceId, initial: nil)
    let dict = composition??.takeRetainedValue() as? [String: Any]
    return (dict?[kAudioAggregateDeviceIsPrivateKey] as? Int) == 1
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
