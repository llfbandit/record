#if os(macOS)

import Foundation

// Captures with the primary engine. When it cannot keep the chosen input, it starts the fallback instead.
// The decision is made once, in start(). After that every call goes to the engine that runs.
final class InputFallbackCapture: CaptureEngine {
  private let m_primary: CaptureEngine
  private let m_makeFallback: () throws -> CaptureEngine
  private var m_running: CaptureEngine

  init(primary: CaptureEngine, makeFallback: @escaping () throws -> CaptureEngine) {
    m_primary = primary
    m_makeFallback = makeFallback
    m_running = primary
  }

  func start() throws -> RecordConfig {
    do {
      return try m_primary.start()
    } catch is InputNotKept {
      // The primary left nothing behind. Capture the same input another way.
      let fallback = try m_makeFallback()
      let effective = try fallback.start()
      m_running = fallback
      return effective
    }
  }

  func pause() { m_running.pause() }

  func resume() throws { try m_running.resume() }

  @discardableResult
  func stop(delete: Bool) -> String? { m_running.stop(delete: delete) }

  var amplitude: Float { m_running.amplitude }
}

#endif
