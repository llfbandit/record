import AVFoundation
import Foundation

class RecorderFileDelegate: NSObject, AudioRecordingFileDelegate, AVCaptureFileOutputRecordingDelegate {
  private var m_audioSession: AVCaptureSession?
  private var m_audioOutput: AVCaptureAudioFileOutput?
  private var m_path: String?
  private var m_amplitude:Float = -160.0
  private var m_stopCb: ((String?) -> ())?
  
  init(onPause: @escaping () -> (), onStop: @escaping () -> ()) {}
  
  func start(config: RecordConfig, path: String) throws {
    try deleteFile(path: path)
    
    let audioSession = AVCaptureSession()
    
    let dev: AVCaptureInput?
    do {
      dev = try getInputDevice(device: config.device)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: "\(error)")
    }
  
    guard let dev = dev else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Input device not found from available list."
      )
    }
    guard audioSession.canAddInput(dev) else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Input device cannot be added to the capture session."
      )
    }
    
    audioSession.beginConfiguration()

    // Add input device
    audioSession.addInput(dev)
    // Add output
    let audioOutput = AVCaptureAudioFileOutput()
    audioSession.addOutput(audioOutput)

    // Set audioSettings *after* adding to session, otherwise it is ignored
    let outputSettings = try getOutputSettings(config: config)
    audioOutput.audioSettings = outputSettings
    
    audioSession.commitConfiguration()
    
    audioSession.startRunning()

    audioOutput.startRecording(
      to: URL(fileURLWithPath: path),
      outputFileType: getFileTypeFromSettings(outputSettings),
      recordingDelegate: self
    )
    
    m_audioOutput = audioOutput
    m_audioSession = audioSession
    m_path = path
  }
  
  func stop(completionHandler: @escaping (String?) -> ()) {
    m_audioOutput?.stopRecording()
    m_audioOutput = nil
    m_audioSession?.stopRunning()
    m_audioSession = nil
    
    m_stopCb = completionHandler
  }
  
  func pause() {
    m_audioOutput?.pauseRecording()
  }

  func resume() {
    m_audioOutput?.resumeRecording()
  }
  
  func cancel() throws {
    stop { _ in
      do {
        guard let path = self.m_path else { return }
        try self.deleteFile(path: path)
      } catch {
        print(error)
      }
    }
  }
  
  func getAmplitude() -> Float {
    var current: Float?
    if let audioOutput = m_audioOutput {
      current = audioOutput.connections.first?.audioChannels.first?.averagePowerLevel
    }
    
    return current ?? -160
  }
  
  func dispose() {
    stop { path in }
  }
  
  public func fileOutput(_ output: AVCaptureFileOutput,
                         didFinishRecordingTo outputFileURL: URL,
                         from connections: [AVCaptureConnection],
                         error: Error?) {
    if let error = error as? NSError,
       let success = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool,
       !success {
      print(error)
    }

    m_stopCb?(m_path)
    m_stopCb = nil
  }
  
  private func deleteFile(path: String) throws {
    do {
      let fileManager = FileManager.default
      
      if fileManager.fileExists(atPath: path) {
        try fileManager.removeItem(atPath: path)
      }
    } catch {
      throw RecorderError.error(
        message: "Failed to delete recording",
        details: error.localizedDescription
      )
    }
  }
}
