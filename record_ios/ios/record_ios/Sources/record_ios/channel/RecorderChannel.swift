import AVFoundation
import Flutter

// Owns the recorders and answers the shared calls. The plugin answers the rest.
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

  // Returns false when only the plugin can answer the call.
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "record", message: "Failed to parse call.arguments from Flutter.", details: nil))
      return true
    }

    switch call.method {
    // These read the machine, not a recorder. We answer them before any lookup.
    case "hasPermission":      hasPermission(args, result)
    case "isEncoderSupported": isEncoderSupported(args, result)
    case "listInputDevices":   listInputDevices(result)

    case "create":  create(args, result)
    case "dispose": disposeRecorder(args, result)

    case "start":
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "record", message: "Call missing mandatory parameter path.", details: nil))
        return true
      }
      withRecorder(args, result) { controller in
        self.run(result: result) { try controller.start(config: try RecordConfig.fromMap(args), path: path) }
      }

    case "startStream":
      withRecorder(args, result) { controller in
        self.run(result: result) { try controller.startStream(config: try RecordConfig.fromMap(args)) }
      }

    case "stop":
      withRecorder(args, result) { controller in
        let path = controller.stop()
        DispatchQueue.main.async { result(path) }
      }

    case "cancel":
      withRecorder(args, result) { controller in self.run(result: result) { controller.cancel() } }

    case "pause":
      withRecorder(args, result) { controller in self.run(result: result) { controller.pause() } }

    case "resume":
      withRecorder(args, result) { controller in self.run(result: result) { try controller.resume() } }

    case "isPaused":
      withRecorder(args, result) { controller in self.run(result: result) { controller.isPaused } }

    case "isRecording":
      withRecorder(args, result) { controller in self.run(result: result) { controller.isRecording } }

    case "getAmplitude":
      withRecorder(args, result) { controller in
        self.run(result: result) { () -> [String: Float] in
          let amplitude = controller.amplitude()
          return ["current": amplitude.current, "max": amplitude.max]
        }
      }

    default:
      return false
    }

    return true
  }

  func dispose() {
    m_queue.async {
      for entry in self.m_entries.values { entry.controller.dispose() }
      self.m_entries = [:]
    }
  }

  // MARK: - For the plugin's own calls

  /// Runs block on the recorder queue. Fails when the recorder does not exist.
  func withPlatform(_ args: [String: Any], _ result: @escaping FlutterResult, _ block: @escaping (P) -> Void) {
    withEntry(args, result) { block($0.platform) }
  }

  /// Runs a throwing block on the current queue and answers on the main thread.
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

  private func withRecorder(
    _ args: [String: Any],
    _ result: @escaping FlutterResult,
    _ block: @escaping (RecorderController) -> Void
  ) {
    withEntry(args, result) { block($0.controller) }
  }

  private func withEntry(
    _ args: [String: Any],
    _ result: @escaping FlutterResult,
    _ block: @escaping (Entry) -> Void
  ) {
    guard let recorderId = recorderId(args, result) else { return }

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

  private func recorderId(_ args: [String: Any], _ result: @escaping FlutterResult) -> String? {
    guard let recorderId = args["recorderId"] as? String else {
      result(FlutterError(code: "record", message: "Call missing mandatory parameter recorderId.", details: nil))
      return nil
    }
    return recorderId
  }

  private func create(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let recorderId = recorderId(args, result) else { return }

    let stateChannel = FlutterEventChannel(
      name: "com.llfbandit.record/events/\(recorderId)", binaryMessenger: m_messenger)
    let stateHandler = StateStreamHandler()
    stateChannel.setStreamHandler(stateHandler)

    let recordChannel = FlutterEventChannel(
      name: "com.llfbandit.record/eventsRecord/\(recorderId)", binaryMessenger: m_messenger)
    let recordHandler = RecordStreamHandler()
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
    guard let encoder = args["encoder"] as? String else {
      result(FlutterError(code: "record", message: "Call missing mandatory parameter encoder.", details: nil))
      return
    }

    result(m_queries.supportedEncoders.contains(encoder))
  }

  private func listInputDevices(_ result: @escaping FlutterResult) {
    // This touches the audio session, so we keep it on the recorder queue.
    m_queue.async {
      self.run(result: result) { try self.m_queries.devices.list().map { $0.toMap() } }
    }
  }
}
