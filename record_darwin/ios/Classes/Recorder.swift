import Foundation
import AVFoundation

class Recorder: NSObject, RecorderProtocol, AVCaptureAudioDataOutputSampleBufferDelegate, AVAudioRecorderDelegate {
  private var m_audioSession: AVCaptureSession?
  private var m_audioOutput: AVCaptureOutput?
  private var m_dev: AVCaptureInput?
  private var m_audioRecorder: AVAudioRecorder?
  private var m_path: String?
  private var m_maxAmplitude: Float = -160.0
  private var m_state: RecordState = RecordState.stop
  private var m_config: RecordConfig?
  
  private var m_stateEventHandler: StateStreamHandler
  private var m_recordEventHandler: RecordStreamHandler
  
  init(stateEventHandler: StateStreamHandler, recordEventHandler: RecordStreamHandler) {
    m_stateEventHandler = stateEventHandler
    m_recordEventHandler = recordEventHandler
  }
  
  public func dispose() {
    stopRecording()
  }
  
  public func start(config: RecordConfig, path: String) throws {
    stopRecording()
    
    try deleteFile(path: path)
    
    try setupAudioSession(config)
    
    let url = URL(fileURLWithPath: path)
    let audioRecorder = try AVAudioRecorder(url: url, settings: getOutputSettings(config: config))
    audioRecorder.delegate = self
    audioRecorder.isMeteringEnabled = true
    
    // start recording
    DispatchQueue.main.async {
      audioRecorder.record()
    }
    
    m_audioRecorder = audioRecorder
    m_config = config
    m_path = path
    updateState(RecordState.record)
  }
  
  public func startStream(config: RecordConfig) throws {
    stopRecording()
    
    try setupAudioSession(config)
    
    let dev = try getRecordingInputDevice(config: config)
    
    let audioOut = createDataOutput(config)
    
    let session = try createRecordingSession(config, dev: dev, audioOut: audioOut)
    
    // start recording
    session.startRunning()
    
    m_audioOutput = audioOut
    m_audioSession = session
    m_config = config
    m_dev = dev
    m_path = nil
    updateState(RecordState.record)
  }
  
  public func stop() -> String? {
    guard isRecording() else {
      return nil
    }
    
    let path = m_path
    
    stopRecording()
    updateState(RecordState.stop)
    
    return path
  }
  
  public func pause() {
    if m_state == .record {
      if let audioRecorder = m_audioRecorder {
        audioRecorder.pause()
      } else {
        m_dev?.ports.forEach({ port in port.isEnabled = false })
      }
      
      updateState(RecordState.pause)
    }
  }
  
  public func resume() throws {
    if isPaused() {
      if let audioRecorder = m_audioRecorder {
        audioRecorder.record()
      } else {
        m_dev?.ports.forEach({ port in port.isEnabled = true })
      }
      
      updateState(RecordState.record)
    }
  }
  
  public func isPaused() -> Bool {
    return m_state == .pause
  }
  
  public func isRecording() -> Bool {
    return m_state != .stop
  }
  
  public func getAmplitude() -> [String : Float] {
    var amp = ["current" : -160.0, "max" : -160.0] as [String : Float]
    
    if m_state == .record {
      m_audioRecorder?.updateMeters()
      
      guard let current = m_audioRecorder?.averagePower(forChannel: 0) else {
        return amp
      }
      
      if (current > m_maxAmplitude) {
        m_maxAmplitude = current
      }
      
      amp["current"] = current
      amp["max"] = m_maxAmplitude
    }
    
    return amp
  }
  
  private func stopRecording() {
    if let output = m_audioOutput {
      if let dataOutput = output as? AVCaptureAudioDataOutput {
        dataOutput.setSampleBufferDelegate(nil, queue: nil)
      }
    }
    m_audioOutput = nil

    if let audioRecorder = m_audioRecorder {
      audioRecorder.stop()
      m_audioRecorder = nil
    }
    
    m_audioSession?.stopRunning()
    m_audioSession = nil
    
    m_dev = nil
    m_maxAmplitude = -160.0
    m_path = nil
    m_state = .stop
    m_config = nil
    
    NotificationCenter.default.removeObserver(onAudioSessionInterruption)
  }
  
  private func createDataOutput(_ config: RecordConfig) -> AVCaptureAudioDataOutput {
    let audioOut = AVCaptureAudioDataOutput()
    
    let audioCaptureQueue = DispatchQueue(label: "com.llfbandit.record.queue", attributes: [])
    audioOut.setSampleBufferDelegate(self, queue: audioCaptureQueue)
    
    return audioOut
  }

  private func setupAudioSession(_ config: RecordConfig) throws {
    let audioSession = AVAudioSession.sharedInstance()
    let options: AVAudioSession.CategoryOptions = [.allowBluetooth]
    
    do {
      try audioSession.setCategory(.record, options: options)
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: "setCategory: \(error.localizedDescription)")
    }
    
    do {
      try audioSession.setPreferredSampleRate((config.samplingRate <= 48000) ? Double(config.samplingRate) : 48000.0)
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: "setPreferredSampleRate: \(error.localizedDescription)")
    }
    
    do {
      try audioSession.setActive(true) // Must be done before setting channels & buffer duration
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: "setActive: \(error.localizedDescription)")
    }
    
    do {
      try audioSession.setPreferredInputNumberOfChannels(
        (config.numChannels > audioSession.inputNumberOfChannels) ? audioSession.inputNumberOfChannels : max(1, config.numChannels)
      )
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: "setPreferredInputNumberOfChannels: \(error.localizedDescription)")
    }
    
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: nil,
      using: onAudioSessionInterruption)
  }
  
  private func createRecordingSession(_ config: RecordConfig,
                                      dev: AVCaptureDeviceInput,
                                      audioOut: AVCaptureOutput) throws -> AVCaptureSession {
    let session = AVCaptureSession()
    session.beginConfiguration()
    
    // Add input
    if !session.canAddInput(dev) {
      throw RecorderError.start(message: "Failed to start recording", details: "Input device cannot be added to the capture session.")
    }
    session.addInput(dev)
    
    // Add output
    guard session.canAddOutput(audioOut) else {
      throw RecorderError.start(message: "Failed to start recording", details: "AVCaptureOutput cannot be added to the capture session.")
    }
    session.addOutput(audioOut)
    
    session.commitConfiguration()
    
    return session
  }
  
  private func updateState(_ state: RecordState) {
    m_state = state
    
    if let eventSink = m_stateEventHandler.eventSink {
      eventSink(state.rawValue)
    }
  }
  
  // MARK: AVCaptureAudioDataOutputSampleBufferDelegate
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    if isPaused() {
      return
    }
    
    writeToStream(sampleBuffer, config: m_config, recordEventHandler: m_recordEventHandler)
  }
  
  private func onAudioSessionInterruption(notification: Notification) -> Void {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }
    
    if type == AVAudioSession.InterruptionType.began {
      pause()
    } else if type == AVAudioSession.InterruptionType.ended {
      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
      
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      
      do {
        if options.contains(.shouldResume) {
          try resume()
        } else {
          _ = stop()
        }
      } catch {
      }
    }
  }
}
