import Foundation

// Something the engine did by itself. It can come from any thread.
enum CaptureEvent {
  case chunk(Data)
  // Capture cannot continue. The controller ends the take.
  case terminated(Error)
}

// Runs one take. After stop(), it cannot be used again.
protocol CaptureEngine: AnyObject {
  // Starts to capture. Returns the config we really use.
  func start() throws -> RecordConfig

  func pause()
  func resume() throws

  // Frees everything. Returns the recorded file if there is one.
  @discardableResult
  func stop(delete: Bool) -> String?

  // Last input level in dB, `silenceDb` if nothing is captured.
  var amplitude: Float { get }
}
