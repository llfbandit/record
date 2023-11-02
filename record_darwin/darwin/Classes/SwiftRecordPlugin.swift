import AVFoundation

#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
import Cocoa
#endif

public class SwiftRecordPlugin: NSObject, FlutterPlugin {
  // Instanciate plugin and register it to flutter engine
  public static func register(with registrar: FlutterPluginRegistrar) {
#if os(iOS)
    let binaryMessenger = registrar.messenger()
#else
    let binaryMessenger = registrar.messenger
#endif
    
    let methodChannel = FlutterMethodChannel(name: "com.llfbandit.record/messages", binaryMessenger: binaryMessenger)
    
    let instance = SwiftRecordPlugin(binaryMessenger: binaryMessenger)
    
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
  }
  
  // MARK: Plugin
  private var m_binaryMessenger: FlutterBinaryMessenger
  
  private var m_recorders = [String: Recorder]()
  
  init(binaryMessenger: FlutterBinaryMessenger) {
    self.m_binaryMessenger = binaryMessenger
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
      let args = call.arguments as! [String : Any]
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
    
    let config = RecordConfig(
      encoder: encoder,
      bitRate: args["bitRate"] as? Int ?? 128000,
      sampleRate: args["sampleRate"] as? Int ?? 44100,
      numChannels: args["numChannels"] as? Int ?? 2,
      device: device,
      autoGain: args["autoGain"] as? Bool ?? false,
      echoCancel: args["echoCancel"] as? Bool ?? false,
      noiseSuppress: args["noiseSuppress"] as? Bool ?? false
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
