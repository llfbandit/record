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
