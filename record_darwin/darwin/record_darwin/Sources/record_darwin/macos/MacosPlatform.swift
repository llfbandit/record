#if os(macOS)

import AVFoundation

// macOS: CoreAudio for inputs.
final class MacosPlatform: RecorderPlatform {
  private let macosDevices = MacosDeviceRegistry()
  private let macosEnvironment = MacosAudioEnvironment()

  var devices: DeviceRegistry { macosDevices }
  var environment: AudioEnvironment { macosEnvironment }

  // AVAudioEngine may go back to the system default input, whatever we ask. When that happens
  // to a chosen input, AVCaptureSession captures it. Voice processing is not available there,
  // so a take with echo cancel or auto gain fails instead, see `MacosAudioEnvironment.verifyInput`.
  func makeEngine(
    config: RecordConfig,
    target: CaptureTarget,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine {
    let engine = AudioEngineCapture(config: config, target: target, environment: environment, onEvent: onEvent)

    guard !config.echoCancel, !config.autoGain,
          let uid = config.device?.id,
          let deviceId = CoreAudioDevices.id(forUid: uid),
          deviceId != CoreAudioDevices.defaultInputId() else { return engine }

    return InputFallbackCapture(primary: engine) {
      // The config may hold a raw id. AVCaptureDevice only knows the UID.
      guard let captureUid = CoreAudioDevices.deviceUid(of: deviceId),
            let device = AVCaptureDevice(uniqueID: captureUid) else {
        throw RecorderError.startFailed("The input cannot be captured: \(uid).")
      }
      return CaptureSessionCapture(config: config, target: target, device: device, onEvent: onEvent)
    }
  }
}

#endif
