import Foundation

// What the controller should do about an environment change.
enum PolicyAction {
  case pause
  case resume
}

// The only place that decides what `audioInterruption` means.
enum EnvironmentPolicy {
  // Nil when the config asks to do nothing.
  static func react(config: RecordConfig, event: EnvironmentEvent) -> PolicyAction? {
    switch event {
    case .interrupted:
      return config.audioInterruption != .none ? .pause : nil

    case .interruptionEnded(let shouldResume):
      return shouldResume && config.audioInterruption == .pauseResume ? .resume : nil
    }
  }
}
