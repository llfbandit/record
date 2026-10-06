import Foundation

// All that changes between platforms. One per recorder.
protocol RecorderPlatform: AnyObject {
  var supportedEncoders: Set<String> { get }
  var devices: DeviceRegistry { get }
  var environment: AudioEnvironment { get }
  var inputRoute: InputRoute { get }

  func makeEngine(
    config: RecordConfig,
    target: CaptureTarget,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine
}

// Both platforms capture the same way. Tests give their own engines.
extension RecorderPlatform {
  var supportedEncoders: Set<String> {
    [
      AudioEncoder.aacLc.rawValue,
      AudioEncoder.aacEld.rawValue,
      AudioEncoder.aacHe.rawValue,
      AudioEncoder.flac.rawValue,
      AudioEncoder.opus.rawValue,
      AudioEncoder.pcm16bits.rawValue,
      AudioEncoder.wav.rawValue,
    ]
  }

  func makeEngine(
    config: RecordConfig,
    target: CaptureTarget,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine {
    AudioEngineCapture(config: config, target: target, route: inputRoute, onEvent: onEvent)
  }
}
