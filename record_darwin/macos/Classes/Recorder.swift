import Foundation
import AVFoundation

class Recorder: NSObject, RecorderProtocol, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
  private var m_audioSession: AVCaptureSession?
  private var m_audioOutput: AVCaptureOutput?
  private var m_dev: AVCaptureInput?
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
    
    let dev = try getRecordingInputDevice(config: config)
    
    let audioOut = try createFileOutput(config)
    
    let session = try createRecordingSession(config, dev: dev, audioOut: audioOut)
    
    // start recording
    DispatchQueue.main.async {
      session.startRunning()
      
      audioOut.startRecording(
        to: URL(fileURLWithPath: path),
        outputFileType: AVFileType.m4a,
        recordingDelegate: self
      )
    }
    
    m_audioOutput = audioOut
    m_audioSession = session
    m_config = config
    m_dev = dev
    m_path = path
    updateState(RecordState.record)
  }

  public func startStream(config: RecordConfig) throws {
    stopRecording()
    
    let dev = try getRecordingInputDevice(config: config)
    
    let audioOut = createDataOutput(config)
    
    let session = try createRecordingSession(config, dev: dev, audioOut: audioOut)
    
    // start recording
    DispatchQueue.main.async {
      session.startRunning()
      
    }
    
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
    guard let audioOutput = m_audioOutput, m_state == .record else {
      return
    }
    
    if let fileOutput = audioOutput as? AVCaptureAudioFileOutput {
      fileOutput.pauseRecording()
    } else {
      m_dev?.ports.forEach({ port in port.isEnabled = false })
    }
    
    updateState(RecordState.pause)
  }
  
  public func resume() throws {
    guard let audioOutput = m_audioOutput, isPaused() else {
      return
    }
    
    if let fileOutput = audioOutput as? AVCaptureAudioFileOutput {
      fileOutput.resumeRecording()
    } else {
      m_dev?.ports.forEach({ port in port.isEnabled = true })
    }
    
    updateState(RecordState.record)
  }
  
  public func isPaused() -> Bool {
    return m_state == .pause
  }
  
  public func isRecording() -> Bool {
    return m_state != .stop
  }
  
  public func getAmplitude() -> [String : Float] {
    var amp = ["current" : -160.0, "max" : -160.0] as [String : Float]
    
    if let audioOutput = m_audioOutput {
      let current = audioOutput.connections.first?.audioChannels.first?.averagePowerLevel
      if let current = current {
        if (current > m_maxAmplitude) {
          m_maxAmplitude = current
        }
        
        amp["current"] = min(0.0, max(current, -160.0))
        amp["max"] = min(0.0, max(m_maxAmplitude, -160.0))
      }
    }
    
    return amp
  }
  
  private func stopRecording() {
    if let output = m_audioOutput {
      if let fileOutput = output as? AVCaptureAudioFileOutput {
        fileOutput.stopRecording()
      }
      if let dataOutput = output as? AVCaptureAudioDataOutput {
        dataOutput.setSampleBufferDelegate(nil, queue: nil)
      }
    }
    m_audioOutput = nil
    
    m_audioSession?.stopRunning()
    m_audioSession = nil
    
    m_dev = nil
    m_maxAmplitude = -160.0
    m_path = nil
    m_state = .stop
    m_config = nil
  }
  
  private func createFileOutput(_ config: RecordConfig) throws -> AVCaptureAudioFileOutput {
    let audioOut = AVCaptureAudioFileOutput()
    audioOut.audioSettings = try getOutputSettings(config: config)

    return audioOut
  }
  
  private func createDataOutput(_ config: RecordConfig) -> AVCaptureAudioDataOutput {
    let audioOut = AVCaptureAudioDataOutput()
    audioOut.audioSettings = getInputSettings(config: config)
    
    let audioCaptureQueue = DispatchQueue(label: "com.llfbandit.record.queue", attributes: [])
    audioOut.setSampleBufferDelegate(self, queue: audioCaptureQueue)
    
    return audioOut
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
  
  // MARK: AVCaptureFileOutputRecordingDelegate
  public func fileOutput(_ output: AVCaptureFileOutput,
                         didFinishRecordingTo outputFileURL: URL,
                         from connections: [AVCaptureConnection],
                         error: Error?) {
    if let error = error as? NSError {
      if let success = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool, !success {
        print(error)
      }
      if error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] == nil {
        print(error)
      }
    }
  }
}
