import AVFoundation

// All that changes between platforms. One per recorder.
protocol RecorderPlatform: AnyObject {
  var supportedEncoders: Set<String> { get }
  var devices: DeviceRegistry { get }
  var environment: AudioEnvironment { get }
  var inputRoute: InputRoute { get }

  // See OpenInput. The config is the take's.
  func openInput(
    on uid: String?,
    config: RecordConfig,
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
    onChange: @escaping () -> Void
  ) throws -> CaptureInput

  func makeEngine(
    config: RecordConfig,
    target: CaptureTarget,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine
}

// Both platforms run takes with AudioEngineCapture. Tests give their own engines.
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
    let input = InputTracker(route: inputRoute, devices: devices) { onEvent(.inputChanged) }
    return AudioEngineCapture(
      config: config,
      target: target,
      input: input,
      openInput: { [self] in try openInput(on: $0, config: config, onBuffer: $1, onChange: $2) },
      onEvent: onEvent
    )
  }
}
