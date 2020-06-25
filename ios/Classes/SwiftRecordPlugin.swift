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
  var hasPermission = false
  var audioRecorder: AVAudioRecorder?

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "start":
        let args = call.arguments as! [String : Any]
        start(
          path: args["path"] as? String ?? "",
          outputFormat: args["outputFormat"] as? Int ?? 0,
          bitRate: args["bitRate"] as? Int ?? 128000,
          samplingRate: args["samplingRate"] as? Float ?? 44100.0,
          result: result);
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

  func hasPermission(_ result: @escaping FlutterResult) {
    switch AVAudioSession.sharedInstance().recordPermission {
      case AVAudioSession.RecordPermission.granted:
        hasPermission = true
        break
      case AVAudioSession.RecordPermission.denied:
        hasPermission = false
        break
      case AVAudioSession.RecordPermission.undetermined:
        AVAudioSession.sharedInstance().requestRecordPermission() { [unowned self] allowed in
          DispatchQueue.main.async {
            self.hasPermission = allowed
          }
        }
        break
      default:
        break
    }

    result(hasPermission)
  }

  func start(path: String, outputFormat: Int, bitRate: Int, samplingRate: Float, result: @escaping FlutterResult) {
    stopRecording()

    let settings = [
      AVFormatIDKey: getOutputFormat(outputFormat),
      //AVEncoderBitRateKey: bitRate, // does not work at all, messing the record without error
      AVSampleRateKey: samplingRate,
      AVNumberOfChannelsKey: 2,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ] as [String : Any]

    do {
      try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, options: AVAudioSession.CategoryOptions.defaultToSpeaker)
      try AVAudioSession.sharedInstance().setActive(true)

      audioRecorder = try AVAudioRecorder(url: URL(string: path)!, settings: settings)
      audioRecorder!.delegate = self
      audioRecorder!.record()

      isRecording = true
      result(nil)
    } catch {
      result(FlutterError(code: "", message: "Failed to start recording", details: nil))
    }
  }

  func stop(_ result: @escaping FlutterResult) {
    stopRecording()
    result(nil)
  }

  func stopRecording() {
    audioRecorder?.stop()
    audioRecorder = nil
    isRecording = false
  }

  func getOutputFormat(_ outputFormat: Int) -> Int {
    switch(outputFormat) {
    case 1:
      return Int(kAudioFormatAMR);
    case 2:
      return Int(kAudioFormatAMR_WB);
    default:
      return Int(kAudioFormatMPEG4AAC_HE);
    }
  }
}
