import Foundation

// Why a take ended. Dart reads the name.
enum StopReason: String {
  // The app ended it: stop(), cancel(), dispose(), or a new start().
  case stop
  case routeChange
  case interruption
  case error
}

// The end of a take.
struct RecordStop: Equatable {
  let reason: StopReason
  // Nil after cancel(), and for a stream.
  let path: String?
  // What failed, for .error.
  let error: String?

  init(_ reason: StopReason, path: String?, error: Error? = nil) {
    self.reason = reason
    self.path = path
    self.error = error?.localizedDescription
  }

  // Dart reads the state from it too.
  func toMap() -> [String: Any] {
    var map: [String: Any] = ["state": RecordState.stop.rawValue, "reason": reason.rawValue]
    if let path { map["path"] = path }
    if let error { map["error"] = error }
    return map
  }
}
