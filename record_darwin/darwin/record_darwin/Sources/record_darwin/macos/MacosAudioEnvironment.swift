#if os(macOS)

import Foundation

// macOS has no audio session and sends no interruption. So there is nothing to do.
final class MacosAudioEnvironment: AudioEnvironment {
  // macOS never sends an event, so the handler is dropped.
  func bind(onEvent: @escaping (EnvironmentEvent) -> Void) {}

  func prepare(_ config: RecordConfig) throws {}

  func activate() throws {}

  func release() {}
}

#endif
