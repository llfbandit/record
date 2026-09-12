import Foundation

public enum RecorderError: Error {
  case error(message: String, details: String?)
}

public enum RecordState: Int {
  case pause = 0
  case record = 1
  case stop = 2
}

// The level we report when we capture nothing.
let silenceDb: Float = -160.0
