import AVFoundation

// Something that happened in the audio environment.
enum EnvironmentEvent {
  case interrupted
  case interruptionEnded(shouldResume: Bool)
}

// The system audio state a take needs. There is one per recorder, so it outlives each take.
protocol AudioEnvironment: AnyObject {
  // Set once before the first prepare(). The platform calls it from its own thread.
  var onEvent: ((EnvironmentEvent) -> Void)? { get set }

  // Takes the audio state for this take. If it throws, it cleans up everything.
  func prepare(_ config: RecordConfig) throws

  // Takes it again after something else stole it.
  func activate() throws

  // Gives it back. prepare() starts the next take.
  func release()

  // Points a running capture graph at the device, when the platform selects it per node.
  func bindInput(_ device: Device?, to node: AVAudioInputNode) throws
}

extension AudioEnvironment {
  func bindInput(_ device: Device?, to node: AVAudioInputNode) throws {}
}
