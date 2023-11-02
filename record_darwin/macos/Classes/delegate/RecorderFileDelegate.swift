import AVFoundation
import Foundation

class RecorderFileDelegate: NSObject, AudioRecordingFileDelegate, AVCaptureFileOutputRecordingDelegate {
  private var audioSession: AVCaptureSession?
  private var audioOutput: AVCaptureAudioFileOutput?
  private var path: String?
  private var amplitude:Float = -160.0
  private var stopCb: ((String?) -> ())?
  
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
    let outputSettings = try getOutputSettings(config: config)
    let audioOutput = AVCaptureAudioFileOutput()
    audioOutput.audioSettings = outputSettings
    audioSession.addOutput(audioOutput)
    
    audioSession.commitConfiguration()
    
    audioSession.startRunning()

    audioOutput.startRecording(
      to: URL(fileURLWithPath: path),
      outputFileType: getFileTypeFromSettings(outputSettings),
      recordingDelegate: self
    )
    
    self.audioOutput = audioOutput
    self.audioSession = audioSession
    self.path = path
  }
  
  func stop(completionHandler: @escaping (String?) -> ()) {
    audioOutput?.stopRecording()
    audioOutput = nil
    audioSession?.stopRunning()
    audioSession = nil
    
    stopCb = completionHandler
  }
  
  func pause() {
    audioOutput?.pauseRecording()
  }

  func resume() {
    audioOutput?.resumeRecording()
  }
  
  func cancel() throws {
    stop { _ in
      do {
        guard let path = self.path else { return }
        try self.deleteFile(path: path)
      } catch {
        print(error)
      }
    }
  }
  
  func getAmplitude() -> Float {
    var current: Float?
    if let audioOutput = audioOutput {
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

    stopCb?(path)
    stopCb = nil
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
