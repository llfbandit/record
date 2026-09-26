import AVFoundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

// Owns the recorders and answers the shared calls.
final class RecorderChannel<P: RecorderPlatform> {
  private struct Entry {
    let id: String
    let controller: RecorderController
    let platform: P
  }

  private let m_messenger: FlutterBinaryMessenger
  private let m_makePlatform: () -> P
  // Answers the calls that read the machine, not a recorder.
  private let m_queries: P

  private let m_queue = DispatchQueue(label: "com.record.pluginQueue", qos: .userInitiated)
  private var m_entries = [String: Entry]()

  init(messenger: FlutterBinaryMessenger, makePlatform: @escaping () -> P) {
    m_messenger = messenger
    m_makePlatform = makePlatform
    m_queries = makePlatform()
  }

  // Answers the shared calls. Returns the arguments when only the plugin can answer.
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> [String: Any]? {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "record", message: "Failed to parse call.arguments from Flutter.", details: nil))
      return nil
    }

    switch call.method {
    // These read the machine, not a recorder, so no lookup is needed.
    case "hasPermission":      hasPermission(args, result)
    case "isEncoderSupported": isEncoderSupported(args, result)
    case "listInputDevices":   listInputDevices(result)

    case "create":  create(args, result)
    case "dispose": disposeRecorder(args, result)

    case "start":
      guard let path: String = require("path", in: args, result) else { return nil }
      perform(args, result) { try $0.start(config: try RecordConfig.fromMap(args), path: path) }

    case "startStream":  perform(args, result) { try $0.startStream(config: try RecordConfig.fromMap(args)) }
    case "stop":         perform(args, result) { $0.stop() }
    case "cancel":       perform(args, result) { $0.cancel() }
    case "pause":        perform(args, result) { $0.pause() }
    case "resume":       perform(args, result) { try $0.resume() }
    case "isPaused":     perform(args, result) { $0.isPaused }
    case "isRecording":  perform(args, result) { $0.isRecording }

    case "getAmplitude":
      perform(args, result) { controller -> [String: Float] in
        let amplitude = controller.amplitude()
        return ["current": amplitude.current, "max": amplitude.max]
      }

    default:
      return args
    }

    return nil
  }

  // Sync: the app may exit right after, and each file must be closed first.
  func dispose() {
    m_queue.sync {
      for entry in self.m_entries.values { entry.controller.dispose() }
      self.m_entries = [:]
    }
  }

  // MARK: - For the plugin's own calls

  /// The value at key, or answers an error and returns nil.
  func require<T>(_ key: String, in args: [String: Any], _ result: @escaping FlutterResult) -> T? {
    guard let value = args[key] as? T else {
      result(FlutterError(code: "record", message: "Call missing mandatory parameter \(key).", details: nil))
      return nil
    }
    return value
  }

  /// Runs block on the recorder queue. Fails if it does not exist.
  func withPlatform(_ args: [String: Any], _ result: @escaping FlutterResult, _ block: @escaping (P) -> Void) {
    withEntry(args, result) { block($0.platform) }
  }

  /// Runs a throwing block, answers on the main thread.
  func run<T>(result: @escaping FlutterResult, _ block: () throws -> T) {
    do {
      let value = try block()
      DispatchQueue.main.async {
        if T.self == Void.self { result(nil) } else { result(value) }
      }
    } catch let RecorderError.error(message, details) {
      DispatchQueue.main.async { result(FlutterError(code: "record", message: message, details: details)) }
    } catch {
      DispatchQueue.main.async { result(FlutterError(code: "record", message: error.localizedDescription, details: nil)) }
    }
  }

  // MARK: - Private

  // Runs block on the recorder queue and answers with what it returns.
  private func perform<T>(
    _ args: [String: Any],
    _ result: @escaping FlutterResult,
    _ block: @escaping (RecorderController) throws -> T
  ) {
    withEntry(args, result) { entry in self.run(result: result) { try block(entry.controller) } }
  }

  private func withEntry(
    _ args: [String: Any],
    _ result: @escaping FlutterResult,
    _ block: @escaping (Entry) -> Void
  ) {
    guard let recorderId: String = require("recorderId", in: args, result) else { return }

    m_queue.async {
      guard let entry = self.m_entries[recorderId] else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "record",
            message: "Recorder has not yet been created or has already been disposed.",
            details: nil
          ))
        }
        return
      }
      block(entry)
    }
  }

  private func create(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let recorderId: String = require("recorderId", in: args, result) else { return }

    let stateChannel = FlutterEventChannel(
      name: "com.llfbandit.record/events/\(recorderId)", binaryMessenger: m_messenger)
    let stateHandler = EventStreamHandler()
    stateChannel.setStreamHandler(stateHandler)

    let recordChannel = FlutterEventChannel(
      name: "com.llfbandit.record/eventsRecord/\(recorderId)", binaryMessenger: m_messenger)
    let recordHandler = EventStreamHandler()
    recordChannel.setStreamHandler(recordHandler)

    let configChanged = FlutterMethodChannel(
      name: "com.llfbandit.record/configChanged/\(recorderId)", binaryMessenger: m_messenger)

    let platform = m_makePlatform()
    let controller = RecorderController(
      queue: m_queue,
      platform: platform,
      sink: ChannelSink(state: stateHandler, records: recordHandler, configChanged: configChanged)
    )

    m_queue.async {
      self.m_entries[recorderId]?.controller.dispose()
      self.m_entries[recorderId] = Entry(id: recorderId, controller: controller, platform: platform)
      DispatchQueue.main.async { result(nil) }
    }
  }

  private func disposeRecorder(_ args: [String: Any], _ result: @escaping FlutterResult) {
    withEntry(args, result) { entry in
      self.m_entries.removeValue(forKey: entry.id)
      entry.controller.dispose()
      DispatchQueue.main.async { result(nil) }
    }
  }

  private func hasPermission(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let request = args["request"] as? Bool ?? true

    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      result(true)

    case .notDetermined:
      guard request else { return result(false) }
      AVCaptureDevice.requestAccess(for: .audio) { allowed in
        DispatchQueue.main.async { result(allowed) }
      }

    default:
      result(false)
    }
  }

  private func isEncoderSupported(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let encoder: String = require("encoder", in: args, result) else { return }

    result(m_queries.supportedEncoders.contains(encoder))
  }

  private func listInputDevices(_ result: @escaping FlutterResult) {
    // Touches the audio session, so it stays on the recorder queue.
    m_queue.async {
      self.run(result: result) { try self.m_queries.devices.list().map { $0.toMap() } }
    }
  }
}
