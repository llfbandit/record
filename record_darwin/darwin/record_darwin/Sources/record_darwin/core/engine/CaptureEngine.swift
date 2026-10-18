import Foundation

// Something the engine did by itself. It can come from any thread.
enum CaptureEvent {
  case chunk(Data)
  // The audio input or the device list changed. The controller reads inputState.
  case inputChanged
  // Capture cannot continue. The controller ends the take.
  case terminated(Error)
}

// What became of the input a take captures from.
enum InputState {
  // Capture runs on it.
  case ok
  // It is still there, but capture does not run on it: paused, or stopped or moved by the system.
  case stopped
  // It is gone.
  case lost
}

// Runs one take. After stop(), it cannot be used again.
protocol CaptureEngine: AnyObject {
  // Starts to capture. Returns the config we really use.
  func start() throws -> RecordConfig

  func pause()
  // Throws RecorderError.noInputDevice when the input in use is gone.
  func resume() throws

  // Only reads. It never changes capture.
  var inputState: InputState { get }

  // Starts capture again on the input in use. Throws RecorderError.noInputDevice when it is gone.
  func restart() throws

  // Frees everything. Returns the recorded file if there is one.
  @discardableResult
  func stop(delete: Bool) -> String?

  // Last input level in dB, `silenceDb` if nothing is captured.
  var amplitude: Float { get }
}
