import AVFoundation
import XCTest

@testable import record_darwin

// A take on fake inputs, through a real output.
final class AudioEngineCaptureTests: XCTestCase {
  private final class FakeInput: CaptureInput {
    let format: AVAudioFormat
    private let m_onBuffer: (AVAudioPCMBuffer) -> Void
    private(set) var isRunning = false
    var isCurrent = true
    // Seconds it still holds. It sends them when it pauses, like HalInput.
    var held: Double = 0

    init(format: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
      self.format = format
      m_onBuffer = onBuffer
    }

    func start() throws { isRunning = true }
    func pause() {
      isRunning = false
      send(held)
      held = 0
    }
    func close() { isRunning = false }

    // Sends `seconds` of silence, in tap-sized buffers of 0.1 s.
    func send(_ seconds: Double) {
      let frames = AVAudioFrameCount(format.sampleRate / 10)
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
      buffer.frameLength = frames
      for _ in 0..<Int(seconds * 10) { m_onBuffer(buffer) }
    }
  }

  // After a move, the old input can still send a buffer. It is dropped, not an error.
  func testABufferFromTheOldInputIsDropped() throws {
    let formats = [
      AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!,
      AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 2)!,
    ]
    var inputs: [FakeInput] = []
    var bytes = 0
    var failures = 0
    let capture = AudioEngineCapture(
      config: makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 1),
      target: .stream,
      input: InputTracker(route: FakeInputRoute(), devices: FakeDeviceRegistry()) {},
      openInput: { _, onBuffer, _ in
        let input = FakeInput(format: formats[inputs.count], onBuffer: onBuffer)
        inputs.append(input)
        return input
      },
      onEvent: { event in
        switch event {
        case .chunk(let data): bytes += data.count
        case .terminated: failures += 1
        case .inputChanged: break
        }
      }
    )

    _ = try capture.start()
    inputs[0].send(1)
    // The input changed its format. restart() moves the take to a new one.
    inputs[0].isCurrent = false
    try capture.restart()
    inputs[0].send(0.1)
    inputs[1].send(1)
    _ = capture.stop(delete: false)

    XCTAssertEqual(failures, 0)
    // 16 bit mono at 16 kHz, for 2 s. The resamplers hold back a few frames.
    XCTAssertEqual(Double(bytes), 64000, accuracy: 64000 * 0.02)
  }

  // What the input sends as it pauses was captured before the pause. It goes in the take.
  func testThePauseKeepsWhatTheInputHeld() throws {
    var input: FakeInput?
    var bytes = 0
    let capture = AudioEngineCapture(
      config: makeConfig(encoder: "pcm16bits", sampleRate: 16000, numChannels: 1),
      target: .stream,
      input: InputTracker(route: FakeInputRoute(), devices: FakeDeviceRegistry()) {},
      openInput: { _, onBuffer, _ in
        let fake = FakeInput(format: AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!, onBuffer: onBuffer)
        input = fake
        return fake
      },
      onEvent: { event in
        if case .chunk(let data) = event { bytes += data.count }
      }
    )

    _ = try capture.start()
    input?.send(1)
    input?.held = 0.5
    capture.pause()
    _ = capture.stop(delete: false)

    // 16 bit mono at 16 kHz, for 1.5 s.
    XCTAssertEqual(Double(bytes), 48000, accuracy: 48000 * 0.02)
  }
}
