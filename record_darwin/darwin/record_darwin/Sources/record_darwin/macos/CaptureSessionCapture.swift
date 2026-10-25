#if os(macOS)

import AVFoundation

// Captures a chosen input with AVCaptureSession.
// It is the way out when AVAudioEngine goes back to the system default input and ignores the chosen one.
// It has no voice processing. Buffers come in the size the session picks, not `streamBufferSize`.
final class CaptureSessionCapture: NSObject, CaptureEngine, AVCaptureAudioDataOutputSampleBufferDelegate {
  private let m_config: RecordConfig
  private let m_target: CaptureTarget
  private let m_device: AVCaptureDevice
  private let m_onEvent: (CaptureEvent) -> Void
  private let m_queue = DispatchQueue(label: "record_darwin.capture_session")
  private let m_lock = NSLock()

  private var m_session: AVCaptureSession?
  private var m_observers: [NSObjectProtocol] = []
  private var m_format: AVAudioFormat?
  private var m_output: CaptureOutput?
  // Set while start() waits for the first buffer.
  private var m_firstBuffer: DispatchSemaphore?
  private var m_isPaused = false
  private var m_amplitude = silenceDb

  init(
    config: RecordConfig,
    target: CaptureTarget,
    device: AVCaptureDevice,
    onEvent: @escaping (CaptureEvent) -> Void
  ) {
    m_config = config
    m_target = target
    m_device = device
    m_onEvent = onEvent
  }

  func start() throws -> RecordConfig {
    if case .file(let path) = m_target { try RecordFile.delete(at: path) }

    // The device's own rate and channels, as float. Outputs convert from it, like from a tap.
    guard let description = CMAudioFormatDescriptionGetStreamBasicDescription(m_device.activeFormat.formatDescription)?.pointee,
          let srcFormat = AVAudioFormat(standardFormatWithSampleRate: description.mSampleRate, channels: description.mChannelsPerFrame)
    else {
      throw RecorderError.startFailed("No audio input is available.")
    }

    let negotiated = try FormatPolicy.negotiate(for: m_config, input: srcFormat)
    let output = try m_target.makeOutput(
      settings: negotiated.settings, config: negotiated.effective, srcFormat: srcFormat, onEvent: m_onEvent)

    let session = AVCaptureSession()
    let dataOutput = AVCaptureAudioDataOutput()
    dataOutput.audioSettings = srcFormat.settings
    dataOutput.setSampleBufferDelegate(self, queue: m_queue)

    let firstBuffer = DispatchSemaphore(value: 0)
    do {
      let input = try RecorderError.wrapping("AVCaptureDeviceInput") { try AVCaptureDeviceInput(device: m_device) }
      guard session.canAddInput(input), session.canAddOutput(dataOutput) else {
        throw RecorderError.startFailed("The input cannot be captured.")
      }
      session.addInput(input)
      session.addOutput(dataOutput)

      m_lock.withLock {
        m_format = srcFormat
        m_firstBuffer = firstBuffer
        m_output = output
      }
      session.startRunning()

      // Same check as the engine: a running session may still give no audio.
      guard firstBuffer.wait(timeout: .now() + firstBufferTimeout) == .success else {
        throw RecorderError.startFailed("The input gave no audio in \(Int(firstBufferTimeout * 1000)) ms.")
      }
    } catch {
      m_lock.withLock {
        m_output = nil
        m_firstBuffer = nil
      }
      session.stopRunning()
      _ = output.close(delete: true)
      throw error
    }
    m_session = session

    // Listen only now, so a failure during start() is the error of start().
    m_observers = [
      NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: m_device, queue: nil) {
        [weak self] _ in
        self?.terminate(Self.inputGoneError)
      },
      NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) {
        [weak self] notification in
        let cause = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
        self?.terminate(
          RecorderError.error(message: "Recording stopped", details: cause?.localizedDescription ?? "The capture session failed."))
      },
    ]

    return negotiated.effective
  }

  func pause() {
    m_lock.withLock { m_isPaused = true }
    m_session?.stopRunning()
  }

  func resume() throws {
    m_session?.startRunning()
    m_lock.withLock { m_isPaused = false }
  }

  @discardableResult
  func stop(delete: Bool) -> String? {
    for observer in m_observers { NotificationCenter.default.removeObserver(observer) }
    m_observers = []
    m_session?.stopRunning()
    m_session = nil

    let output = m_lock.withLock { () -> CaptureOutput? in
      let output = m_output
      m_output = nil
      return output
    }

    // Closing writes the end of the file.
    return output?.close(delete: delete)
  }

  var amplitude: Float {
    m_lock.withLock { m_output == nil ? silenceDb : m_amplitude }
  }

  // Runs under the lock, so stop() cannot close the output during a write.
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    let failure = m_lock.withLock { () -> (CaptureOutput, Error)? in
      guard !m_isPaused, let output = m_output, let format = m_format else { return nil }

      let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
      buffer.frameLength = frames
      guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
        sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
      ) == noErr else { return nil }

      m_firstBuffer?.signal()
      m_firstBuffer = nil

      m_amplitude = AudioEngineCapture.peakDb(buffer)
      do {
        try output.write(buffer)
        return nil
      } catch {
        // Clear it, so the next buffer does not report the error again.
        m_output = nil
        return (output, error)
      }
    }
    guard let failure else { return }

    // Keeps what was written before.
    _ = failure.0.close(delete: false)
    m_onEvent(.terminated(failure.1))
  }

  // MARK: - Private

  // The capture cannot continue. End the take and keep the file, once.
  private func terminate(_ error: Error) {
    let output = m_lock.withLock { () -> CaptureOutput? in
      let output = m_output
      m_output = nil
      return output
    }
    guard let output else { return }

    _ = output.close(delete: false)
    m_onEvent(.terminated(error))
  }

  private static let inputGoneError = RecorderError.error(
    message: "Recording stopped",
    details: "The audio input changed or is gone."
  )
}

#endif
