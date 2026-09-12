import Foundation

// The iOS side: AVAudioSession for state and inputs, AVAudioRecorder for file capture.
final class IosPlatform: RecorderPlatform {
  let supportedEncoders: Set<String> = [
    AudioEncoder.aacLc.rawValue,
    AudioEncoder.aacEld.rawValue,
    AudioEncoder.amrNb.rawValue,
    AudioEncoder.flac.rawValue,
    AudioEncoder.opus.rawValue,
    AudioEncoder.pcm16bits.rawValue,
    AudioEncoder.wav.rawValue,
  ]

  let iosDevices: IosDeviceRegistry
  let iosEnvironment: IosAudioEnvironment

  var devices: DeviceRegistry { iosDevices }
  var environment: AudioEnvironment { iosEnvironment }

  init() {
    let devices = IosDeviceRegistry()
    iosDevices = devices
    iosEnvironment = IosAudioEnvironment(devices: devices)
  }

  func makeFileEngine(
    config: RecordConfig,
    path: String,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine {
    AvAudioRecorderEngine(config: config, path: path, devices: iosDevices, onEvent: onEvent)
  }

  func makeStreamEngine(
    config: RecordConfig,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine {
    StreamCaptureEngine(config: config, environment: iosEnvironment, onEvent: onEvent)
  }
}
