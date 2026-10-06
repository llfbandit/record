import Foundation

// Something that happened in the audio environment.
enum EnvironmentEvent {
  case interrupted
  case interruptionEnded(shouldResume: Bool)
}

// The system audio state. One per recorder, it outlives each take.
protocol AudioEnvironment: AnyObject {
  // Called once, before the first prepare(). Runs on the platform thread.
  func bind(onEvent: @escaping (EnvironmentEvent) -> Void)

  // Takes the audio state. Cleans up if it throws.
  func prepare(_ config: RecordConfig) throws

  // Takes it again after something else stole it.
  func activate() throws

  // Gives it back. prepare() starts the next take.
  func release()
}
