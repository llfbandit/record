import Flutter
import UIKit
import AVFoundation

public class SwiftRecordPlugin: NSObject, FlutterPlugin, AVAudioRecorderDelegate {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.llfbandit.record", binaryMessenger: registrar.messenger())
    let instance = SwiftRecordPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  var isRecording = false
  var hasPermissions = false
  var audioRecorder: AVAudioRecorder!

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "start":
        let args = call.arguments as! [String : Any]
        start(
          args["path"] as? String,
          args["outputFormat"] as? int,
          args["bitRate"] as? int,
          args["samplingRate"] as? int,
          result);
        break
      case "stop":
        stop(result)
        break
      case "isRecording":
        result(isRecording)
        break
      case "hasPermission":
        hasPermission(result);
      default:
        result(FlutterMethodNotImplemented)
        break
    }
  }

  func hasPermission(result: @escaping FlutterResult) {
    switch AVAudioSession.sharedInstance().recordPermission() {
      case AVAudioSession.RecordPermission.granted:
        hasPermissions = true
        break
      case AVAudioSession.RecordPermission.denied:
        hasPermissions = false
        break
      case AVAudioSession.RecordPermission.undetermined:
        AVAudioSession.sharedInstance().requestRecordPermission() { [unowned self] allowed in
          DispatchQueue.main.async {
            if allowed {
              self.hasPermissions = true
            } else {
              self.hasPermissions = false
            }
          }
        }
        break
      default:
        break
    }

    result(hasPermissions)
  }

  func start(path: String, outputFormat: int, bitRate: int, samplingRate: int, result: @escaping FlutterResult) {
    stopRecording()

    let settings = [
      AVFormatIDKey: getOutputFormat(outputFormat),
      AVEncoderBitRateKey: bitRate,
      AVSampleRateKey: samplingRate,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    do {
      try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord, with: AVAudioSessionCategoryOptions.defaultToSpeaker)
      try AVAudioSession.sharedInstance().setActive(true)

      audioRecorder = try AVAudioRecorder(url: URL(string: path)!, settings: settings)
      audioRecorder.delegate = self
      audioRecorder.record()

      isRecording = true
      result(nil)
    } catch {
      result(FlutterError(code: "", message: "Failed to start recording", details: nil))
    }
  }

  func stop(result: @escaping FlutterResult) {
    stopRecording()
    result(null)
  }

  func stopRecording() {
    audioRecorder.stop()
    audioRecorder = nil
  }

  func getOutputFormat(int outputFormat): AudioFormatID {
    switch(outputFormat) {
      case 1:
        return kAudioFormatAMR;
      case 2:
        return kAudioFormatAMR_WB;
      case 0:
      default:
        return kAudioFormatMPEG4AAC_HE;
    }
  }
}