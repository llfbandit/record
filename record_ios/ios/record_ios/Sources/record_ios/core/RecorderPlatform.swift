import Foundation

// All that changes between platforms, in one place. One per recorder.
protocol RecorderPlatform: AnyObject {
  var supportedEncoders: Set<String> { get }
  var devices: DeviceRegistry { get }
  var environment: AudioEnvironment { get }

  func makeFileEngine(
    config: RecordConfig,
    path: String,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine

  func makeStreamEngine(
    config: RecordConfig,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine
}
