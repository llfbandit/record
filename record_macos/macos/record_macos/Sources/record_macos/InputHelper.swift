import AVFoundation
import Foundation

func listInputs() throws -> [Device] {
  var devices: [Device] = []

  listInputDevices().forEach { input in
    devices.append(Device(id: input.uniqueID, label: input.localizedName))
  }
  
  return devices
}

func listInputDevices() -> [AVCaptureDevice] {
  let discoverySession = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInMicrophone],
    mediaType: .audio, position: .unspecified
  )
  
  return discoverySession.devices
}

func getInputDevice(device: Device?) throws -> AVCaptureDeviceInput? {
  guard let device = device else {
    // try to select default device
    let defaultDevice = AVCaptureDevice.default(for: .audio)
    guard let defaultDevice = defaultDevice else {
      return nil
    }
    
    return try AVCaptureDeviceInput(device: defaultDevice)
  }

  // find the given device
  let devs = listInputDevices()
  let captureDev = devs.first { dev in
    dev.uniqueID == device.id
  }
  guard let captureDev = captureDev else {
    return nil
  }
  
  return try AVCaptureDeviceInput(device: captureDev)
}

func getAudioDeviceIDFromUID(uid: String) -> AudioDeviceID? {
  var propertySize: UInt32 = 0
  var status: OSStatus = noErr
  
  // Get the number of devices
  var propertyAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  status = AudioObjectGetPropertyDataSize(
    AudioObjectID(kAudioObjectSystemObject),
    &propertyAddress,
    0,
    nil,
    &propertySize
  )
  if status != noErr {
    return nil
  }
  
  // Get the device IDs
  let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
  var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
  status = AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject),
    &propertyAddress,
    0,
    nil,
    &propertySize,
    &deviceIDs
  )
  if status != noErr {
    return nil
  }

  // Get device UID
  for deviceID in deviceIDs {
    // Support lookup by devicezID rather than uid
    if String(deviceID) == uid {
      return deviceID
    }

    propertyAddress.mSelector = kAudioDevicePropertyDeviceUID
    propertySize = UInt32(MemoryLayout<CFString>.size)
    var deviceUID: Unmanaged<CFString>?

    status = AudioObjectGetPropertyData(
      deviceID,
      &propertyAddress,
      0,
      nil,
      &propertySize,
      &deviceUID
    )
    if status == noErr && uid == deviceUID?.takeRetainedValue() as String? {
      return deviceID
    }
  }
  
  return nil
}
