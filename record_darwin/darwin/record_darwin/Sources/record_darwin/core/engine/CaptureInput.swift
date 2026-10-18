import AVFoundation

// One input that feeds a take, with its format. A move to another input makes a new one.
// On iOS, EngineInput uses AVAudioEngine. On macOS, HalInput uses a HAL unit.
protocol CaptureInput: AnyObject {
  // What it gives.
  var format: AVAudioFormat { get }

  var isRunning: Bool { get }

  // Still on the input in use, in this format. Else starting it would fail, or crash the app.
  var isCurrent: Bool { get }

  func start() throws

  func pause()

  // Frees it. It cannot be used again.
  func close()
}

// Opens a new input on the device the route just bound, with this UID. It is not started.
// onBuffer runs on its own thread. onChange runs on any thread, when the input changes by itself.
typealias OpenInput = (
  _ uid: String?,
  _ onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
  _ onChange: @escaping () -> Void
) throws -> CaptureInput
