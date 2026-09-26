import Foundation

public enum RecorderError: Error {
  case error(message: String, details: String?)
}

extension RecorderError {
  static func startFailed(_ details: String) -> RecorderError {
    .error(message: "Failed to start recording", details: details)
  }

  // Runs one system call. Its error becomes ours, with the call name.
  static func wrapping<T>(
    _ call: String,
    failure message: String = "Failed to start recording",
    _ body: () throws -> T
  ) throws -> T {
    do {
      return try body()
    } catch {
      throw RecorderError.error(message: message, details: "\(call): \(error.localizedDescription)")
    }
  }
}
