import Flutter
import UIKit
import AVFoundation

public class SwiftRecordPlugin: NSObject, FlutterPlugin, AVAudioRecorderDelegate, FlutterStreamHandler {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(name: "com.llfbandit.record/messages", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "com.llfbandit.record/events", binaryMessenger: registrar.messenger())

    let instance = SwiftRecordPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
    registrar.addApplicationDelegate(instance)
  }

  fileprivate var isRecording = false
  fileprivate var isPaused = false
  fileprivate var audioRecorder: AVAudioRecorder?
  fileprivate var path: String?
  fileprivate var maxAmplitude:Float = -160.0
  fileprivate var eventSink: FlutterEventSink?

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "start":
        let args = call.arguments as! [String : Any]
        path = args["path"] as? String

        if path == nil {
          let directory = NSTemporaryDirectory()
          let fileName = UUID().uuidString + ".m4a"

            path = NSURL.fileURL(withPathComponents: [directory, fileName])?.absoluteString
        }

        start(
          path: path!,
          encoder: args["encoder"] as! String,
          bitRate: args["bitRate"] as? Int ?? 128000,
          samplingRate: args["samplingRate"] as? Int ?? 44100,
          numChannels: args["numChannels"] as? Int ?? 2,
          device: args["device"] as? [String : Any],
          result: result)
        break
      case "stop":
        stop(result)
        break
      case "pause":
        pause(result)
        break
      case "resume":
        resume(result)
        break
      case "isPaused":
        result(isPaused)
        break
      case "isRecording":
        result(isRecording)
        break
      case "hasPermission":
        hasPermission(result)
        break
      case "getAmplitude":
        getAmplitude(result)
        break
      case "isEncoderSupported":
        let args = call.arguments as! [String : Any]
        let encoder = args["encoder"] as! String
        let settings = getEncoderSettings(encoder)
        result(settings != nil)
        break
      case "listInputDevices":
        result(listInputDevices())
        break
      case "dispose":
        dispose(result)
        break
      default:
        result(FlutterMethodNotImplemented)
        break
    }
  }

  public func applicationWillTerminate(_ application: UIApplication) {
    stopRecording()
  }

  fileprivate func hasPermission(_ result: @escaping FlutterResult) {
    switch AVAudioSession.sharedInstance().recordPermission {
      case .granted:
        result(true)
        break
      case .denied:
        result(false)
        break
      case .undetermined:
        AVAudioSession.sharedInstance().requestRecordPermission() { allowed in
          DispatchQueue.main.async {
            result(allowed)
          }
        }
        break
      default:
        break
    }
  }

  fileprivate func start(path: String, encoder: String, bitRate: Int, samplingRate: Int, numChannels: Int, device: [String: Any]?, result: @escaping FlutterResult) {
    stopRecording()

    let settings = getSettings(
      encoder: encoder,
      bitRate: bitRate,
      samplingRate: samplingRate,
      numChannels: numChannels,
      device: device)

    let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth]

    do {
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: options)
      try AVAudioSession.sharedInstance().setActive(true)

      let url = URL(string: path) ?? URL(fileURLWithPath: path)
      audioRecorder = try AVAudioRecorder(url: url, settings: settings)
      audioRecorder!.delegate = self
      audioRecorder!.isMeteringEnabled = true
      audioRecorder!.record()

      updateState(1)
      result(nil)
    } catch {
      result(FlutterError(code: "-1", message: "Failed to start recording", details: "\(error)"))
    }
  }

  fileprivate func stop(_ result: @escaping FlutterResult) {
    stopRecording()
    updateState(2)
    result(path)
  }
    
  fileprivate func pause(_ result: @escaping FlutterResult) {
    audioRecorder?.pause()
    updateState(0)
    result(nil)
  }
    
  fileprivate func resume(_ result: @escaping FlutterResult) {
    if isPaused {
      audioRecorder?.record()
      updateState(1)
    }
    
    result(nil)
  }

    fileprivate func isEncoderSupported(encoder: String) -> Bool {
    let encoderSettings = getEncoderSettings(encoder)
    return encoderSettings != nil
  }

  fileprivate func getAmplitude(_ result: @escaping FlutterResult) {
    var amp = ["current" : -160.0, "max" : -160.0] as [String : Float]

    if isRecording {
      audioRecorder?.updateMeters()
      
      guard let current = audioRecorder?.averagePower(forChannel: 0) else {
        result(amp)
        return
      }

      if (current > maxAmplitude) {
        maxAmplitude = current
      }

      amp["current"] = current
      amp["max"] = maxAmplitude
    }

    result(amp)
  }

  fileprivate func stopRecording() {
    audioRecorder?.stop()
    audioRecorder = nil
    isRecording = false
    isPaused = false
    maxAmplitude = -160.0
  }

  fileprivate func dispose(_ result: @escaping FlutterResult) {
    stopRecording()
    result(nil)
  }

  fileprivate func getSettings(encoder: String, bitRate: Int, samplingRate: Int, numChannels: Int, device: [String: Any]?) -> [String : Any] {
    let settings = [
      AVEncoderBitRateKey: bitRate,
      AVSampleRateKey: samplingRate,
      AVNumberOfChannelsKey: numChannels,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ] as [String : Any]

    var encoderSettings = getEncoderSettings(encoder)
    // Defaults to ACC LD
    if (encoderSettings == nil) {
      encoderSettings = [AVFormatIDKey : Int(kAudioFormatMPEG4AAC)]
    }

    return settings.merging(encoderSettings!, uniquingKeysWith: { (_, last) in last })
  }

  // https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers
  fileprivate func getEncoderSettings(_ encoder: String) -> [String : Any]? {    
    switch(encoder) {
    case "aacEld":
      return [AVFormatIDKey : Int(kAudioFormatMPEG4AAC_ELD)]
    case "aacHe":
      return [AVFormatIDKey : Int(kAudioFormatMPEG4AAC_HE_V2)]
    case "amrNb":
      return [AVFormatIDKey : Int(kAudioFormatAMR)]
    case "amrWb":
      return [AVFormatIDKey : Int(kAudioFormatAMR_WB)]
    case "opus":
      return [AVFormatIDKey : Int(kAudioFormatOpus)]
    case "flac":
      return [AVFormatIDKey : Int(kAudioFormatFLAC)]
    case "pcm8bit":
      return [
        AVFormatIDKey : Int(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: 8,
      ]
    case "pcm16bit":
      return [
        AVFormatIDKey : Int(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: 16,
      ]
    case "aacLc":
      return [AVFormatIDKey : Int(kAudioFormatMPEG4AAC)]
    default:
        return nil
    }
  }

  fileprivate func listInputDevices() -> [[String : Any]] {
    return []
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink) -> FlutterError? {

    self.eventSink = events
    return nil
  }
    
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  fileprivate func updateState(_ state: Int) {
    switch (state) {
      case 0:
        isRecording = true
        isPaused = true
        break
      case 1:
        isRecording = true
        isPaused = false
        break
      default:
        isRecording = false
        isPaused = false
        break
    }

    if let _eventSink = eventSink {
      _eventSink(state)
    }    
  }
}
