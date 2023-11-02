import AVFoundation
import Foundation

class RecorderFileDelegate: NSObject, AudioRecordingFileDelegate, AVAudioRecorderDelegate {
  private var audioRecorder: AVAudioRecorder?
  private var path: String?

  func start(config: RecordConfig, path: String) throws {
    try deleteFile(path: path)

    try initAVAudioSession(config: config)

    let url = URL(fileURLWithPath: path)

    let recorder = try AVAudioRecorder(url: url, settings: getOutputSettings(config: config))

    recorder.delegate = self
    recorder.isMeteringEnabled = true
    recorder.prepareToRecord()
    
    recorder.record()
    
    audioRecorder = recorder
    self.path = path
  }

  func stop(completionHandler: @escaping (String?) -> ()) {
    audioRecorder?.stop()
    audioRecorder = nil

    completionHandler(path)
    
    path = nil
  }
  
  func pause() {
    guard let recorder = audioRecorder, recorder.isRecording else {
      return
    }
    
    recorder.pause()
  }
  
  func resume() {
    audioRecorder?.record()
  }

  func cancel() throws {
    guard let path = path else { return }
    
    stop { path in }
    
    try deleteFile(path: path)
  }
  
  func getAmplitude() -> Float {
    audioRecorder?.updateMeters()
    return audioRecorder?.averagePower(forChannel: 0) ?? -160
  }
  
  func dispose() {
    stop { path in }
  }

  func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
      // Audio recording has stopped
  }
  
  private func deleteFile(path: String) throws {
    do {
      let fileManager = FileManager.default
      
      if fileManager.fileExists(atPath: path) {
        try fileManager.removeItem(atPath: path)
      }
    } catch {
      throw RecorderError.error(message: "Failed to delete previous recording", details: error.localizedDescription)
    }
  }
}
