import Foundation
import AVFoundation

class Recorder {
  private var m_maxAmplitude: Float = -160.0
  private var m_state: RecordState = RecordState.stop
  
  private var m_stateEventHandler: StateStreamHandler
  private var m_recordEventHandler: RecordStreamHandler
  
  private var delegate: AudioRecordingDelegate?
  
  init(stateEventHandler: StateStreamHandler, recordEventHandler: RecordStreamHandler) {
    m_stateEventHandler = stateEventHandler
    m_recordEventHandler = recordEventHandler
  }

  func dispose() {
    stop(completionHandler: {(path) -> () in })
  }
  
  func start(config: RecordConfig, path: String) throws {
    stop(completionHandler: {(path) -> () in })
    
    if !isEncoderSupported(config.encoder) {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "\(config.encoder) not supported."
      )
    }
    
    let delegate = RecorderFileDelegate()
    
    try delegate.start(config: config, path: path)
    
    self.delegate = delegate
    
    updateState(RecordState.record)
  }
  
  func startStream(config: RecordConfig) throws {
    stop(completionHandler: {(path) -> () in })
    
    if config.encoder != AudioEncoder.pcm16bits.rawValue {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "\(config.encoder) not supported in streaming mode."
      )
    }
    
    let delegate = RecorderStreamDelegate()
    
    try delegate.start(config: config, recordEventHandler: m_recordEventHandler)
    
    self.delegate = delegate
    
    updateState(RecordState.record)
  }

  func stop(completionHandler: @escaping (_ path: String?) -> ()) {
    if isRecording() {
      delegate?.stop(completionHandler: {(path) -> () in
        completionHandler(path)
        self.updateState(RecordState.stop)
      })
    }
  }
  
  func pause() {
    if m_state == .record {
      delegate?.pause()
      updateState(RecordState.pause)
    }
  }
  
  func resume()  throws {
    if isPaused() {
      try delegate?.resume()
      updateState(RecordState.record)
    }
  }
  
  func isPaused() -> Bool {
    return m_state == .pause
  }
  
  func isRecording() -> Bool {
    return m_state != .stop
  }
  
  func listInputDevices() throws -> [Device] {
    return try listInputs()
  }
  
  func getAmplitude() -> [String : Float] {
    var amp = ["current" : -160.0, "max" : -160.0] as [String : Float]
    
    let current = delegate?.getAmplitude()
    if let current = current {
      if (current > m_maxAmplitude) {
        m_maxAmplitude = current
      }
      
      amp["current"] = min(0.0, max(current, -160.0))
      amp["max"] = min(0.0, max(m_maxAmplitude, -160.0))
    }
    
    return amp
  }
  
  func cancel() throws {
    if isRecording() {
      try delegate?.cancel()
    }
  }

  private func updateState(_ state: RecordState) {
    m_state = state
    
    if let eventSink = m_stateEventHandler.eventSink {
      DispatchQueue.main.async {
        eventSink(state.rawValue)
      }
    }
  }

  func isEncoderSupported(_ encoder: String) -> Bool {
    switch(encoder) {
    case AudioEncoder.aacLc.rawValue,
      AudioEncoder.aacEld.rawValue, /*"aacHe", "amrNb", "amrWb", "opus",*/
      AudioEncoder.flac.rawValue,
      AudioEncoder.pcm16bits.rawValue,
      AudioEncoder.wav.rawValue:
      return true
    default:
      return false
    }
  }
}
