import AVFoundation
import Flutter
import UIKit

public class RecordIosPlugin: NSObject, FlutterPlugin {
  // Instanciate plugin and register it to flutter engine
  public static func register(with registrar: FlutterPluginRegistrar) {
    let binaryMessenger = registrar.messenger()
    
    let methodChannel = FlutterMethodChannel(name: "com.llfbandit.record/messages", binaryMessenger: binaryMessenger)
    
    let instance = RecordIosPlugin(binaryMessenger: binaryMessenger)
    
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    registrar.addApplicationDelegate(instance)
  }
  
  // MARK: Plugin
  private var m_binaryMessenger: FlutterBinaryMessenger
  
  private var m_recorders = [String: Recorder]()
  
  init(binaryMessenger: FlutterBinaryMessenger) {
    self.m_binaryMessenger = binaryMessenger
  }

  public func applicationWillTerminate(_ application: UIApplication) {
    dispose()
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    dispose()
  }

  func dispose() {
    for (_, recorder) in m_recorders {
      recorder.dispose()
    }
    m_recorders = [:]
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let method = call.method
    
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "record", message: "Failed to parse call.arguments from Flutter.", details: nil))
      return
    }
    
    guard let recorderId = args["recorderId"] as? String else {
      result(FlutterError(code: "record", message: "Call missing mandatory parameter recorderId.", details: nil))
      return
    }
    
    if method == "create" {
      createRecorder(recorderId: recorderId)
      result(nil)
      return
    }
    
    guard let recorder = getRecorder(recorderId: recorderId) else {
      result(FlutterError(code: "record", message: "Recorder has not yet been created or has already been disposed.", details: nil))
      return
    }
    
    switch call.method {
    case "start":
      guard let path = args["path"] as? String else  {
        result(FlutterError(code: "record", message: "Call missing mandatory parameter path.", details: nil))
        return
      }
      
      guard let config = getConfig(args, result: result) else {
        return
      }
      
      do {
        try recorder.start(config: config, path: path)
        result(nil)
      } catch RecorderError.error(let message, let details) {
        result(FlutterError(code: "record", message: message, details: details))
      } catch {
        result(FlutterError(code: "record", message: error.localizedDescription, details: nil))
      }
    case "startStream":
      guard let config = getConfig(args, result: result) else {
        return
      }

      do {
        try recorder.startStream(config: config)
        result(nil)
      } catch RecorderError.error(let message, let details) {
        result(FlutterError(code: "record", message: message, details: details))
      } catch {
        result(FlutterError(code: "record", message: error.localizedDescription, details: nil))
      }
    case "stop":
      recorder.stop { path in
        result(path)
      }
    case "cancel":
      do {
        try recorder.cancel()
        result(nil)
      } catch {
        result(FlutterError(code: "record", message: error.localizedDescription, details: nil))
      }
    case "pause":
      recorder.pause()
      result(nil)
    case "resume":
      do {
        try recorder.resume()
        result(nil)
      } catch {
        result(FlutterError(code: "record", message: error.localizedDescription, details: nil))
      }
    case "isPaused":
      let isPaused = recorder.isPaused()
      result(isPaused)
    case "isRecording":
      let isRecording = recorder.isRecording()
      result(isRecording)
    case "hasPermission":
      hasPermission(result)
    case "getAmplitude":
      let amp = recorder.getAmplitude()
      result(amp)
    case "isEncoderSupported":
      guard let encoder = args["encoder"] as? String else  {
        result(FlutterError(code: "record", message: "Call missing mandatory parameter encoder.", details: nil))
        return
      }
      
      result(recorder.isEncoderSupported(encoder))
    case "listInputDevices":
      do {
        let devices = try recorder.listInputDevices()
        result(devices.map({ dev in dev.toMap() }))
      } catch {
        result(FlutterError(code: "record", message: error.localizedDescription, details: nil))
      }
    case "dispose":
      m_recorders.removeValue(forKey: recorderId)
      recorder.dispose()
      result(nil)
    case "ios.manageAudioSession":
      guard let manage = args["manageAudioSession"] as? Bool else {
        result(FlutterError(code: "record", message: "Failed to parse manageAudioSession from Flutter.", details: nil))
        return
      }
      recorder.manageAudioSession(manage)
      result(nil)
    
    case "ios.setAudioSessionActive":
      guard let active = args["sessionActive"] as? Bool else {
        result(FlutterError(code: "record", message: "Failed to parse sessionActive from Flutter.", details: nil))
        return
      }
      
      do {
        try recorder.setAudioSessionActive(active)
        result(nil)
      } catch {
        result(FlutterError(code: "record", message: error.localizedDescription, details: nil))
      }
      
    case "ios.setAudioSessionCategory":
      guard let category = args["category"] as? String else {
        result(FlutterError(code: "stt", message: "Call missing mandatory parameter category.", details: nil))
        return
      }
      guard let options = args["options"] as? [String] else  {
        result(FlutterError(code: "stt", message: "Call missing mandatory parameter options.", details: nil))
        return
      }
      
      do {
        try recorder.setAudioSessionCategory(toAVCategory(category), options: toAVCategoryOptions(options))
        result(nil)
      } catch {
        result(FlutterError(code: "stt", message: error.localizedDescription, details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
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

  private func getConfig(_ args: [String : Any], result: @escaping FlutterResult) -> RecordConfig? {
    guard let encoder = args["encoder"] as? String else  {
      result(FlutterError(code: "record", message: "Call missing mandatory parameter encoder.", details: nil))
      return nil
    }
    
    var device: Device? = nil
    if let deviceMap = args["device"] as? [String : Any] {
      device = Device(map: deviceMap)
    }

    var iosConfig: IosConfig
    if let iosConfigMap = args["iosConfig"] as? [String : Any] {
      iosConfig = IosConfig(map: iosConfigMap)
    } else {
      iosConfig = IosConfig(map: [:])
    }
    
    var audioInterruption: AudioInterruptionMode = AudioInterruptionMode.pause
    if let value = args["audioInterruption"] as? Int {
      audioInterruption = AudioInterruptionMode(rawValue: value) ?? audioInterruption
    }

    let config = RecordConfig(
      encoder: encoder,
      bitRate: args["bitRate"] as? Int ?? 128000,
      sampleRate: args["sampleRate"] as? Int ?? 44100,
      numChannels: args["numChannels"] as? Int ?? 2,
      device: device,
      autoGain: args["autoGain"] as? Bool ?? false,
      echoCancel: args["echoCancel"] as? Bool ?? false,
      noiseSuppress: args["noiseSuppress"] as? Bool ?? false,
      iosConfig: iosConfig,
      audioInterruption: audioInterruption,
      streamBufferSize: args["streamBufferSize"] as? Int
    )
    
    return config
  }
  
  private func createRecorder(recorderId: String) {
    let stateEventChannel = FlutterEventChannel(name: "com.llfbandit.record/events/\(recorderId)", binaryMessenger: m_binaryMessenger)
    let stateEventHandler = StateStreamHandler()
    stateEventChannel.setStreamHandler(stateEventHandler)
    
    let recordEventChannel = FlutterEventChannel(name: "com.llfbandit.record/eventsRecord/\(recorderId)", binaryMessenger: m_binaryMessenger)
    let recordEventHandler = RecordStreamHandler()
    recordEventChannel.setStreamHandler(recordEventHandler)
    
    let recorder = Recorder(
      stateEventHandler: stateEventHandler,
      recordEventHandler: recordEventHandler
    )
  
    m_recorders[recorderId] = recorder
  }
  
  private func getRecorder(recorderId: String) -> Recorder? {
    return m_recorders[recorderId]
  }
  
  private func toAVCategory(_ category: String) -> AVAudioSession.Category {
      switch category {
      case "ambient": return .ambient
      case "playAndRecord": return .playAndRecord
      case "playback": return .playback
      case "record": return .record
      case "soloAmbient": return .soloAmbient
      default: return .playAndRecord
      }
    }

    private func toAVCategoryOptions(_ options: [String]) -> AVAudioSession.CategoryOptions {
      var result: AVAudioSession.CategoryOptions = []
      
      for option in options {
        switch option {
        case "mixWithOthers": result.insert(.mixWithOthers)
        case "duckOthers": result.insert(.duckOthers)
        case "interruptSpokenAudioAndMixWithOthers": result.insert(.interruptSpokenAudioAndMixWithOthers)
        case "allowBluetooth": result.insert(.allowBluetooth)
        case "allowBluetoothA2DP": result.insert(.allowBluetoothA2DP)
        case "allowAirPlay": result.insert(.allowAirPlay)
        case "defaultToSpeaker": result.insert(.defaultToSpeaker)
        default: break
        }
      }

      return result
    }
}

public class StateStreamHandler: NSObject, FlutterStreamHandler {
  var eventSink: FlutterEventSink?
  
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
}

public class RecordStreamHandler: NSObject, FlutterStreamHandler {
  var eventSink: FlutterEventSink?
  
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
}
