import Foundation

// Why a take is paused. It says what may resume it.
enum PauseReason {
  // Only the user resumes it.
  case user
  // An interruption end may resume it.
  case interruption
}

// What the controller should do about it.
enum TakeAction: Equatable {
  case pause(PauseReason)
  case resume
}

// The only place that decides what `audioInterruption` means.
enum TakePolicy {
  // pausedFor is nil while the take records. Nil when there is nothing to do.
  static func react(to event: EnvironmentEvent, config: RecordConfig, pausedFor: PauseReason?) -> TakeAction? {
    switch event {
    case .interrupted:
      guard pausedFor == nil, config.audioInterruption != .none else { return nil }
      return .pause(.interruption)

    case .interruptionEnded(let shouldResume):
      // A take the user paused stays paused.
      guard pausedFor == .interruption, shouldResume, config.audioInterruption == .pauseResume else { return nil }
      return .resume
    }
  }
}
