import Foundation
import AVFoundation

class Recorder {
  private let minAmplitudeDB: Float = -160.0
  private var m_maxAmplitude: Float = -160.0
  private var m_state: RecordState = RecordState.stop
  
  private var m_stateEventHandler: StateStreamHandler
  private var m_recordEventHandler: RecordStreamHandler
  
  private var m_delegate: AudioRecordingDelegate?
  
  private var m_manageAudioSession = true
  
  init(stateEventHandler: StateStreamHandler, recordEventHandler: RecordStreamHandler) {
    m_stateEventHandler = stateEventHandler
    m_recordEventHandler = recordEventHandler
  }

  func dispose() {
    stop(completionHandler: {(path) -> () in })
    
    m_manageAudioSession = true
  }
  
  func start(config: RecordConfig, path: String) throws {
    stop(completionHandler: {(path) -> () in })
    
    if !isEncoderSupported(config.encoder) {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "\(config.encoder) not supported."
      )
    }
    
    let delegate = RecorderFileDelegate(
      manageAudioSession: m_manageAudioSession,
      onRecord: {() -> () in self.updateState(RecordState.record)},
      onPause: {() -> () in self.updateState(RecordState.pause)},
      onStop: {() -> () in self.updateState(RecordState.stop)}
    )
    
    try delegate.start(config: config, path: path)
    
    self.m_delegate = delegate
  }
  
  func startStream(config: RecordConfig) throws {
    stop(completionHandler: {(path) -> () in })
    
    if config.encoder != AudioEncoder.pcm16bits.rawValue && config.encoder != AudioEncoder.aacLc.rawValue {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "\(config.encoder) not supported in streaming mode."
      )
    }
    
    let delegate = RecorderStreamDelegate(
      manageAudioSession: m_manageAudioSession,
      onRecord: {() -> () in self.updateState(RecordState.record)},
      onPause: {() -> () in self.updateState(RecordState.pause)},
      onStop: {() -> () in self.updateState(RecordState.stop)}
    )
    
    try delegate.start(config: config, recordEventHandler: m_recordEventHandler)
    
    self.m_delegate = delegate
  }

  func stop(completionHandler: @escaping (_ path: String?) -> ()) {
    if isRecording() {
      m_delegate?.stop(completionHandler: {(path) -> () in
        completionHandler(path)
      })
      m_maxAmplitude = minAmplitudeDB
    } else {
      completionHandler(nil)
      updateState(RecordState.stop)
    }
  }
  
  func pause() {
    if m_state == .record {
      m_delegate?.pause()
    }
  }
  
  func resume()  throws {
    if isPaused() {
      try m_delegate?.resume()
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
    var amp = ["current" : minAmplitudeDB, "max" : minAmplitudeDB] as [String : Float]
    
    let current = m_delegate?.getAmplitude()
    if let current = current {
      if (current > m_maxAmplitude) {
        m_maxAmplitude = current
      }
      
      amp["current"] = min(0.0, max(current, minAmplitudeDB))
      amp["max"] = min(0.0, max(m_maxAmplitude, minAmplitudeDB))
    }
    
    return amp
  }
  
  func cancel() throws {
    if isRecording() {
      try m_delegate?.cancel()
    }
  }
  
  func manageAudioSession(_ manage: Bool) {
    m_manageAudioSession = manage
  }
  
  func setAudioSessionActive(_ active: Bool) throws {
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setActive(active)
  }
  
  func setAudioSessionCategory(_ category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) throws {
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(category, options: options)
  }

  private func updateState(_ state: RecordState) {
    if (m_state == state) {
      return
    }

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
      AudioEncoder.aacEld.rawValue, /*"aacHe", "amrNb", "amrWb",*/
      AudioEncoder.flac.rawValue,
      AudioEncoder.opus.rawValue,
      AudioEncoder.pcm16bits.rawValue,
      AudioEncoder.wav.rawValue:
      return true
    default:
      return false
    }
  }
}
