import Foundation

// Why a take is paused. It says what may resume it.
enum PauseReason {
  // Only the user resumes it.
  case user
  // An interruption end may resume it.
  case interruption
  // The input in use is gone. resume() moves capture first.
  case inputLost
}

// Something that happened to a take, not asked by the app.
enum TakeEvent {
  case environment(EnvironmentEvent)
  // The input is still there, but capture does not run on it.
  case inputStopped
  // Capture could not start again, but the input is still there.
  // Without interruptions from the system (macOS), nothing would ever resume the take.
  case restartFailed(sendsInterruptions: Bool)
  // The input in use is gone.
  case inputLost
}

// What the controller should do about it.
enum TakeAction: Equatable {
  case pause(PauseReason)
  case resume
  // Capture starts again on the input in use.
  case restart
  // Capture goes on from the default input.
  case moveToDefault
  // The take ends and keeps its file.
  case end(StopReason)
}

// The only place that decides how a take reacts to the system,
// and what `audioInterruption` and `audioRouteChange` mean.
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
      // A take the user paused, or that lost its input, stays paused. The system says if we may resume.
      case .pauseResume: return pausedFor == .interruption && shouldResume ? .resume : nil
      }

    case .inputStopped:
      // A paused take starts again at resume().
      return pausedFor == nil ? .restart : nil

    case .restartFailed(let sendsInterruptions):
      guard pausedFor == nil else { return nil }
      guard sendsInterruptions else { return .end(.error) }
      // The system holds the input: most likely an interruption we are not told about yet.
      // So its end may resume the take. Else resume() tries again.
      // The take must not pause, and nothing may restart it. So it ends.
      return config.audioInterruption == .none ? .end(.interruption) : .pause(.interruption)

    case .inputLost:
      // Paused for it already. resume() moves capture.
      guard pausedFor != .inputLost else { return nil }

      switch config.audioRouteChange {
      case .follow: return .moveToDefault
      // Like a user pause, so an interruption end cannot resume on another device.
      case .pause: return .pause(.inputLost)
      case .stop: return .end(.routeChange)
      }
    }
  }
}
