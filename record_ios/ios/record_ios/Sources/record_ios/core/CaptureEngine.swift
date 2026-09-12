import Foundation

// Something the engine did by itself. It can come from any thread.
enum CaptureEvent {
  case chunk(Data)
  // Capture cannot continue. The controller ends the take.
  case terminated(Error?)
}

// Runs one take from start to end. Use it once: it is done after stop().
// The handler is set at init and never changes.
protocol CaptureEngine: AnyObject {
  // Starts to capture. Returns the config we really use, which may differ.
  func start() throws -> RecordConfig

  // Returns false if the engine cannot pause or resume now.
  func pause() -> Bool
  func resume() throws -> Bool

  // Frees everything. Returns the recorded file if there is one.
  @discardableResult
  func stop(delete: Bool) -> String?

  // Last input level in dB. It is `silenceDb` when we capture nothing.
  var amplitude: Float { get }
}
