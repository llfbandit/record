#if os(iOS)

import AVFoundation
import Flutter
import UIKit

public class RecordDarwinPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let binaryMessenger = registrar.messenger()
    let methodChannel = FlutterMethodChannel(
      name: "com.llfbandit.record/messages", binaryMessenger: binaryMessenger)
    let instance = RecordDarwinPlugin(binaryMessenger: binaryMessenger)
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
    guard let args = m_recorders.handle(call, result: result) else { return }

    switch call.method {
    case "ios.manageAudioSession":      manageAudioSession(args, result)
    case "ios.setAudioSessionActive":   setAudioSessionActive(args, result)
    case "ios.setAudioSessionCategory": setAudioSessionCategory(args, result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Private

  private func manageAudioSession(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let manage: Bool = m_recorders.require("manageAudioSession", in: args, result) else { return }

    m_recorders.withPlatform(args, result) { platform in
      platform.iosEnvironment.manageAudioSession = manage
      DispatchQueue.main.async { result(nil) }
    }
  }

  private func setAudioSessionActive(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let active: Bool = m_recorders.require("sessionActive", in: args, result) else { return }

    m_recorders.withPlatform(args, result) { platform in
      self.m_recorders.run(result: result) { try platform.iosEnvironment.setSessionActive(active) }
    }
  }

  private func setAudioSessionCategory(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let categoryStr: String = m_recorders.require("category", in: args, result),
          let optionStrs: [String] = m_recorders.require("options", in: args, result) else { return }

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

#elseif os(macOS)

import FlutterMacOS

public class RecordDarwinPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let binaryMessenger = registrar.messenger
    let methodChannel = FlutterMethodChannel(
      name: "com.llfbandit.record/messages", binaryMessenger: binaryMessenger)
    let instance = RecordDarwinPlugin(binaryMessenger: binaryMessenger)
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
  }

  private let m_recorders: RecorderChannel<MacosPlatform>

  init(binaryMessenger: FlutterBinaryMessenger) {
    m_recorders = RecorderChannel(messenger: binaryMessenger) { MacosPlatform() }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    m_recorders.dispose()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // macOS has no call of its own.
    guard m_recorders.handle(call, result: result) != nil else { return }

    result(FlutterMethodNotImplemented)
  }
}

#endif
