import AVFoundation
import Flutter
import UIKit

public class RecordIosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let binaryMessenger = registrar.messenger()
    let methodChannel = FlutterMethodChannel(
      name: "com.llfbandit.record/messages", binaryMessenger: binaryMessenger)
    let instance = RecordIosPlugin(binaryMessenger: binaryMessenger)
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    registrar.addApplicationDelegate(instance)
  }

  private let m_recorders: RecorderChannel<IosPlatform>

  init(binaryMessenger: FlutterBinaryMessenger) {
    m_recorders = RecorderChannel(messenger: binaryMessenger) { IosPlatform() }
  }

  public func applicationWillTerminate(_ application: UIApplication) {
    m_recorders.dispose()
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    m_recorders.dispose()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Calls shared by both platforms.
    if m_recorders.handle(call, result: result) { return }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "record", message: "Failed to parse call.arguments from Flutter.", details: nil))
      return
    }

    switch call.method {
    case "ios.manageAudioSession":      manageAudioSession(args, result)
    case "ios.setAudioSessionActive":   setAudioSessionActive(args, result)
    case "ios.setAudioSessionCategory": setAudioSessionCategory(args, result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Private

  private func manageAudioSession(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let manage = args["manageAudioSession"] as? Bool else {
      result(FlutterError(code: "record", message: "Failed to parse manageAudioSession from Flutter.", details: nil))
      return
    }

    m_recorders.withPlatform(args, result) { platform in
      platform.iosEnvironment.manageAudioSession = manage
      DispatchQueue.main.async { result(nil) }
    }
  }

  private func setAudioSessionActive(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let active = args["sessionActive"] as? Bool else {
      result(FlutterError(code: "record", message: "Failed to parse sessionActive from Flutter.", details: nil))
      return
    }

    m_recorders.withPlatform(args, result) { platform in
      self.m_recorders.run(result: result) { try platform.iosEnvironment.setSessionActive(active) }
    }
  }

  private func setAudioSessionCategory(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let categoryStr = args["category"] as? String,
          let optionStrs = args["options"] as? [String] else {
      result(FlutterError(code: "record", message: "Call missing mandatory parameter category or options.", details: nil))
      return
    }

    m_recorders.withPlatform(args, result) { platform in
      self.m_recorders.run(result: result) {
        try platform.iosEnvironment.setSessionCategory(
          IosConfig.avCategory(from: categoryStr),
          options: IosConfig.avCategoryOptions(from: optionStrs)
        )
      }
    }
  }
}
