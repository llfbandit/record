import Flutter
import UIKit
import AVFoundation

public class SwiftRecordPlugin: NSObject, FlutterPlugin, AVAudioRecorderDelegate {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.llfbandit.record", binaryMessenger: registrar.messenger())
    let instance = SwiftRecordPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
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
          encoder: args["encoder"] as? Int ?? 0,
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
    
  public func applicationWillTerminate(_ application: UIApplication) {
    stopRecording()
  }
    
  public func applicationDidEnterBackground(_ application: UIApplication) {
    stopRecording()
  }

  fileprivate func hasPermission(_ result: @escaping FlutterResult) {
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

  fileprivate func start(path: String, encoder: Int, bitRate: Int, samplingRate: Float, result: @escaping FlutterResult) {
    stopRecording()

    let settings = [
      AVFormatIDKey: getEncoder(encoder),
      AVEncoderBitRateKey: bitRate,
      AVSampleRateKey: samplingRate,
      AVNumberOfChannelsKey: 2,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ] as [String : Any]

    do {
      try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, options: AVAudioSession.CategoryOptions.defaultToSpeaker)
      try AVAudioSession.sharedInstance().setActive(true)

      let url = URL(string: path) ?? URL(fileURLWithPath: path)
      audioRecorder = try AVAudioRecorder(url: url, settings: settings)
      audioRecorder!.delegate = self
      audioRecorder!.record()

      isRecording = true
      result(nil)
    } catch {
      result(FlutterError(code: "", message: "Failed to start recording", details: nil))
    }
  }

  fileprivate func stop(_ result: @escaping FlutterResult) {
    stopRecording()
    result(nil)
  }

  fileprivate func stopRecording() {
    audioRecorder?.stop()
    audioRecorder = nil
    isRecording = false
  }

  // https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers
  fileprivate func getEncoder(_ encoder: Int) -> Int {    
    switch(encoder) {
    case 1:
      return Int(kAudioFormatMPEG4AAC_ELD)
    case 2:
      return Int(kAudioFormatMPEG4AAC_HE)
    case 3:
      return Int(kAudioFormatAMR)
    case 4:
      return Int(kAudioFormatAMR_WB)
    case 5:
      return Int(kAudioFormatOpus)
    default:
      return Int(kAudioFormatMPEG4AAC)
    }
  }
}
