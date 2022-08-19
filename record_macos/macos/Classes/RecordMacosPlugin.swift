import Cocoa
import FlutterMacOS
import AVFoundation

public class RecordMacosPlugin: NSObject, FlutterPlugin, AVCaptureFileOutputRecordingDelegate, FlutterStreamHandler {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(name: "com.llfbandit.record/messages", binaryMessenger: registrar.messenger)
    let eventChannel = FlutterEventChannel(name: "com.llfbandit.record/events", binaryMessenger: registrar.messenger)

    let instance = RecordMacosPlugin()

    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  private var audioSession: AVCaptureSession?
  private var audioOutput: AVCaptureAudioFileOutput?
  private var path: String?
  private var maxAmplitude:Float = -160.0
  private var eventSink: FlutterEventSink?

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
        result(audioOutput?.isRecordingPaused ?? false)
        break
      case "isRecording":
        result(audioOutput?.isRecording ?? false)
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
        result(isEncoderSupported(encoder))
        break
      case "listInputDevices":
      let devs = listInputDevices().map { (device) -> [String : Any] in
        return [
          "id": device.uniqueID,
          "label": device.localizedName,
        ]
      }
        result(devs)
        break
      case "dispose":
        dispose(result)
        break
      default:
        result(FlutterMethodNotImplemented)
        break
    }
  }

  private func hasPermission(_ result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized:
        result(true)
        break
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
          DispatchQueue.main.async {
            result(allowed)
          }
        }
        break
      default:
        result(false)
        break
    }
  }

  private func start(path: String, encoder: String, bitRate: Int, samplingRate: Int, numChannels: Int, device: [String: Any]?, result: @escaping FlutterResult) {
    stopRecording()

    audioSession = AVCaptureSession()
    guard let audioSession = audioSession else {
      result(FlutterError(code: "-1", message: "Failed to start recording", details: "Audio session is nil."))
      return
    }

    let dev: AVCaptureInput?
    do {
      dev = try getInputDevice(device: device)
    } catch {
      result(FlutterError(code: "-2", message: "Failed to start recording", details: "\(error)"))
      return
    }
    
    guard let dev = dev else {
      result(FlutterError(code: "-3", message: "Failed to start recording", details: "Input device not found from available list."))
      return
    }
    guard audioSession.canAddInput(dev) else {
      result(FlutterError(code: "-4", message: "Failed to start recording", details: "Input device cannot be added to the capture session."))
      return
    }

    audioSession.beginConfiguration()

    // Add input device
    audioSession.addInput(dev)
    // Add output
    audioOutput = AVCaptureAudioFileOutput()
    audioOutput!.audioSettings = getSettings(
      encoder: encoder,
      bitRate: bitRate,
      samplingRate: samplingRate,
      numChannels: numChannels)
    audioSession.addOutput(audioOutput!)

    audioSession.commitConfiguration()

    audioSession.startRunning()
    
    audioOutput!.startRecording(
      to: URL(string: path) ?? URL(fileURLWithPath: path),
      outputFileType: AVFileType.m4a,
      recordingDelegate: self
    )

    updateState(1)

    result(nil)
  }

  private func stop(_ result: @escaping FlutterResult) {
    stopRecording()
    updateState(2)
    result(path)
  }
    
  private func pause(_ result: @escaping FlutterResult) {
    audioOutput?.pauseRecording()
    updateState(0)
    result(nil)
  }
    
  private func resume(_ result: @escaping FlutterResult) {
    if audioOutput?.isRecordingPaused ?? false {
      audioOutput?.resumeRecording()
      updateState(1)
    }
    
    result(nil)
  }

  private func isEncoderSupported(_ encoder: String) -> Bool {
    let encoderSettings = getEncoderSettings(encoder)
    return encoderSettings != nil
  }

  private func getAmplitude(_ result: @escaping FlutterResult) {
    var amp = ["current" : -160.0, "max" : -160.0] as [String : Float]

    if let audioOutput = audioOutput {
//      var channels = 0
//      var decibels: Float = 0.0
//      for connection in audioOutput.connections {
//        for audioChannel in connection.audioChannels {
//          decibels += audioChannel.averagePowerLevel
//          channels += 1
//        }
//      }
//
//      decibels /= Float(channels)
//      let current = pow(10.0, 0.05 * decibels) * 20.0
      
      let current = audioOutput.connections.first?.audioChannels.first?.averagePowerLevel
      if let current = current {
        if (current > maxAmplitude) {
          maxAmplitude = current
        }

        amp["current"] = current
        amp["max"] = maxAmplitude
      }
    }

    result(amp)
  }

  private func stopRecording() {
    audioOutput?.stopRecording()
    audioOutput = nil
    audioSession?.stopRunning()
    audioSession = nil
    maxAmplitude = -160.0
  }

  private func dispose(_ result: @escaping FlutterResult) {
    stopRecording()
    result(nil)
  }
  
  public func fileOutput(_ output: AVCaptureFileOutput,
                         didFinishRecordingTo outputFileURL: URL,
                         from connections: [AVCaptureConnection],
                         error: Error?) {
    if let error = error {
      print(error)
    }
  }

  private func getSettings(encoder: String, bitRate: Int, samplingRate: Int, numChannels: Int) -> [String : Any] {
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
  private func getEncoderSettings(_ encoder: String) -> [String : Any]? {
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

  private func listInputDevices() -> [AVCaptureDevice] {
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInMicrophone],
      mediaType: .audio, position: .unspecified
    )
    
    return discoverySession.devices
  }

  private func getInputDevice(device: [String: Any]?) throws -> AVCaptureDeviceInput? {
    guard let device = device else {
      // try to select default device
      let defaultDevice = AVCaptureDevice.default(for: .audio)
      guard let defaultDevice = defaultDevice else {
        return nil
      }

      return try AVCaptureDeviceInput(device: defaultDevice)
    }

    // find the given device
    let devs = listInputDevices()
    let captureDev = devs.first { dev in
      dev.uniqueID == device["id"] as! String
    }
    guard let captureDev = captureDev else {
      return nil
    }
    
    return try AVCaptureDeviceInput(device: captureDev)
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

  private func updateState(_ state: Int) {
    if let _eventSink = eventSink {
      _eventSink(state)
    }
  }
}
