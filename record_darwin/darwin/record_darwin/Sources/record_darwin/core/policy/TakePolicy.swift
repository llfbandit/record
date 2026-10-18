import Foundation

// Why a take is paused. It says what may resume it.
enum PauseReason {
  // Only the user resumes it.
  case user
  // An interruption end may resume it.
  case interruption
}

// Something that happened to a take, not asked by the app.
enum TakeEvent {
  case environment(EnvironmentEvent)
  // The input is still there, but capture does not run on it.
  case inputStopped
  // Capture could not start again, but the input is still there.
  case restartFailed
}

// What the controller should do about it.
enum TakeAction: Equatable {
  case pause(PauseReason)
  case resume
  // Capture starts again on the input in use.
  case restart
}

// The only place that decides how a take reacts to the system, and what `audioInterruption` means.
enum TakePolicy {
  // pausedFor is nil while the take records. Nil when there is nothing to do.
  static func react(to event: TakeEvent, config: RecordConfig, pausedFor: PauseReason?) -> TakeAction? {
    switch event {
    case .environment(.interrupted):
      guard pausedFor == nil, config.audioInterruption != .none else { return nil }
      return .pause(.interruption)

    case .environment(.interruptionEnded(let shouldResume)):
      switch config.audioInterruption {
      // The take never paused, but the system stopped its capture. The app asked to go on recording.
      case .none: return pausedFor == nil ? .restart : nil
      case .pause: return nil
      // A take the user paused stays paused. The system says if we may resume.
      case .pauseResume: return pausedFor == .interruption && shouldResume ? .resume : nil
      }

    case .inputStopped:
      // A paused take starts again at resume().
      return pausedFor == nil ? .restart : nil

    case .restartFailed:
      // The system holds the input: most likely an interruption we are not told about yet.
      // So its end may resume the take. Else resume() tries again.
      guard pausedFor == nil else { return nil }
      // The take must not pause. The interruption end restarts it.
      return config.audioInterruption == .none ? nil : .pause(.interruption)
    }
  }
}
