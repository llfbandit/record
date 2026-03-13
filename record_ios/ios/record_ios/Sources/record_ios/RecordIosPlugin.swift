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
  private let m_recorderQueue: DispatchQueue

  private var m_recorders = [String: Recorder]()

  init(binaryMessenger: FlutterBinaryMessenger) {
    self.m_binaryMessenger = binaryMessenger
    self.m_recorderQueue = DispatchQueue(label: "com.record.pluginQueue", qos: .userInitiated)
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
      handleCreate(recorderId: recorderId)
      result(nil)
      return
    }

    guard let recorder = getRecorder(recorderId: recorderId) else {
      result(FlutterError(code: "record", message: "Recorder has not yet been created or has already been disposed.", details: nil))
      return
    }

    switch call.method {
    case "start":
      handleStart(recorder: recorder, args: args, result: result)
    case "startStream":
      handleStartStream(recorder: recorder, args: args, result: result)
    case "stop":
      handleStop(recorder: recorder, result: result)
    case "cancel":
      handleCancel(recorder: recorder, result: result)
    case "pause":
      handlePause(recorder: recorder, result: result)
    case "resume":
      handleResume(recorder: recorder, result: result)
    case "isPaused":
      handleIsPaused(recorder: recorder, result: result)
    case "isRecording":
      handleIsRecording(recorder: recorder, result: result)
    case "hasPermission":
      handleHasPermission(args: args, result: result)
    case "getAmplitude":
      handleGetAmplitude(recorder: recorder, result: result)
    case "isEncoderSupported":
      handleIsEncoderSupported(recorder: recorder, args: args, result: result)
    case "listInputDevices":
      handleListInputDevices(recorder: recorder, result: result)
    case "dispose":
      handleDispose(recorderId: recorderId, recorder: recorder, result: result)
    case "ios.manageAudioSession":
      handleManageAudioSession(recorder: recorder, args: args, result: result)
    case "ios.setAudioSessionActive":
      handleSetAudioSessionActive(recorder: recorder, args: args, result: result)
    case "ios.setAudioSessionCategory":
      handleSetAudioSessionCategory(recorder: recorder, args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleCreate(recorderId: String) {
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

  private func handleStart(recorder: Recorder, args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["path"] as? String else {
      result(FlutterError(code: "record", message: "Call missing mandatory parameter path.", details: nil))
      return
    }

    guard let config = getConfig(args, result: result) else {
      return
    }

    runWithRecorder(recorder: recorder, result: result) { recorder in
      try recorder.start(config: config, path: path)
    }
  }

  private func handleStartStream(recorder: Recorder, args: [String: Any], result: @escaping FlutterResult) {
    guard let config = getConfig(args, result: result) else {
      return
    }

    runWithRecorder(recorder: recorder, result: result) { recorder in
      try recorder.startStream(config: config)
    }
  }

  private func handleStop(recorder: Recorder, result: @escaping FlutterResult) {
    recorder.stop { path in
      result(path)
    }
  }

  private func handleCancel(recorder: Recorder, result: @escaping FlutterResult) {
    runWithRecorder(recorder: recorder, result: result) { recorder in
      try recorder.cancel()
    }
  }

  private func handlePause(recorder: Recorder, result: @escaping FlutterResult) {
    runWithRecorder(recorder: recorder, result: result) { recorder in
      recorder.pause()
    }
  }

  private func handleResume(recorder: Recorder, result: @escaping FlutterResult) {
    runWithRecorder(recorder: recorder, result: result) { recorder in
      try recorder.resume()
    }
  }

  private func handleIsPaused(recorder: Recorder, result: @escaping FlutterResult) {
    result(recorder.isPaused())
  }

  private func handleIsRecording(recorder: Recorder, result: @escaping FlutterResult) {
    result(recorder.isRecording())
  }

  private func handleHasPermission(args: [String: Any], result: @escaping FlutterResult) {
    let request = args["request"] as? Bool ?? true

    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      result(true)
    case .notDetermined:
      if request {
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
          DispatchQueue.main.async {
            result(allowed)
          }
        }
      } else {
        result(false)
      }
    default:
      result(false)
    }
  }

  private func handleGetAmplitude(recorder: Recorder, result: @escaping FlutterResult) {
    result(recorder.getAmplitude())
  }

  private func handleIsEncoderSupported(recorder: Recorder, args: [String: Any], result: @escaping FlutterResult) {
    guard let encoder = args["encoder"] as? String else {
      result(FlutterError(code: "record", message: "Call missing mandatory parameter encoder.", details: nil))
      return
    }

    result(recorder.isEncoderSupported(encoder))
  }

  private func handleListInputDevices(recorder: Recorder, result: @escaping FlutterResult) {
    runWithRecorder(recorder: recorder, result: result) { recorder in
      let devices = try recorder.listInputDevices()
      return devices.map({ dev in dev.toMap() })
    }
  }

  private func handleDispose(recorderId: String, recorder: Recorder, result: @escaping FlutterResult) {
    runWithRecorder(recorder: recorder, result: result) { recorder in
      self.m_recorders.removeValue(forKey: recorderId)
      recorder.dispose()
    }
  }

  private func handleManageAudioSession(recorder: Recorder, args: [String: Any], result: @escaping FlutterResult) {
    guard let manage = args["manageAudioSession"] as? Bool else {
      result(FlutterError(code: "record", message: "Failed to parse manageAudioSession from Flutter.", details: nil))
      return
    }
    runWithRecorder(recorder: recorder, result: result) { recorder in
      recorder.manageAudioSession(manage)
    }
  }

  private func handleSetAudioSessionActive(recorder: Recorder, args: [String: Any], result: @escaping FlutterResult) {
    guard let active = args["sessionActive"] as? Bool else {
      result(FlutterError(code: "record", message: "Failed to parse sessionActive from Flutter.", details: nil))
      return
    }

    runWithRecorder(recorder: recorder, result: result) { recorder in
      try recorder.setAudioSessionActive(active)
    }
  }

  private func handleSetAudioSessionCategory(recorder: Recorder, args: [String: Any], result: @escaping FlutterResult) {
    guard let category = args["category"] as? String else {
      result(FlutterError(code: "stt", message: "Call missing mandatory parameter category.", details: nil))
      return
    }
    guard let options = args["options"] as? [String] else {
      result(FlutterError(code: "stt", message: "Call missing mandatory parameter options.", details: nil))
      return
    }

    runWithRecorder(recorder: recorder, result: result) { recorder in
      try recorder.setAudioSessionCategory(self.toAVCategory(category), options: self.toAVCategoryOptions(options))
    }
  }

  private func getConfig(_ args: [String : Any], result: @escaping FlutterResult) -> RecordConfig? {
    guard let encoder = args["encoder"] as? String else {
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

  private func getRecorder(recorderId: String) -> Recorder? {
    return m_recorders[recorderId]
  }

  private func runWithRecorder<T>(
    recorder: Recorder,
    result: @escaping FlutterResult,
    _ block: @escaping (Recorder) throws -> T) {

    m_recorderQueue.async {
      do {
        let value = try block(recorder)
        DispatchQueue.main.async {
          if T.self == Void.self {
            result(nil)
          } else {
            result(value)
          }
        }
      } catch RecorderError.error(let message, let details) {
        DispatchQueue.main.async {
          result(FlutterError(code: "record", message: message, details: details))
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "record", message: error.localizedDescription, details: nil))
        }
      }
    }
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
