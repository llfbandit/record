import AVFoundation

@testable import record_darwin

final class FakeCaptureEngine: CaptureEngine {
  let config: RecordConfig
  private let m_onEvent: (CaptureEvent) -> Void

  var effectiveConfig: RecordConfig?
  var startError: Error?
  var resumeError: Error?
  var amplitudeValue = silenceDb
  var recordedPath: String? = "/tmp/take.m4a"

  private(set) var startCount = 0
  private(set) var pauseCount = 0
  private(set) var resumeCount = 0
  private(set) var stopDeleteFlags: [Bool] = []

  init(config: RecordConfig, onEvent: @escaping (CaptureEvent) -> Void) {
    self.config = config
    m_onEvent = onEvent
  }

  func start() throws -> RecordConfig {
    startCount += 1
    if let startError { throw startError }
    return effectiveConfig ?? config
  }

  func pause() {
    pauseCount += 1
  }

  func resume() throws {
    resumeCount += 1
    if let resumeError { throw resumeError }
  }

  @discardableResult
  func stop(delete: Bool) -> String? {
    stopDeleteFlags.append(delete)
    return delete ? nil : recordedPath
  }

  var amplitude: Float { amplitudeValue }

  // Reports like a real engine does, from outside the controller queue.
  func raise(_ event: CaptureEvent) { m_onEvent(event) }
}

final class FakeAudioEnvironment: AudioEnvironment {
  var prepareError: Error?
  var activateError: Error?

  private(set) var prepareCount = 0
  private(set) var activateCount = 0
  private(set) var releaseCount = 0

  private var m_onEvent: (EnvironmentEvent) -> Void = { _ in }

  func bind(onEvent: @escaping (EnvironmentEvent) -> Void) { m_onEvent = onEvent }

  func prepare(_ config: RecordConfig) throws {
    prepareCount += 1
    if let prepareError { throw prepareError }
  }

  func activate() throws {
    activateCount += 1
    if let activateError { throw activateError }
  }

  func release() { releaseCount += 1 }

  // Reports like the system does, from outside the controller queue.
  func raise(_ event: EnvironmentEvent) { m_onEvent(event) }
}

final class FakeDeviceRegistry: DeviceRegistry {
  var devices: [Device] = []

  func list() throws -> [Device] { devices }

  var missingIds: Set<String> = []
  func isAvailable(_ device: Device) -> Bool { !missingIds.contains(device.id) }
}

// Only real engines bind an input. The engine is faked, so nothing calls it.
final class FakeInputRoute: InputRoute {
  func bind(_ deviceId: String?, channels: Int, to engine: AVAudioEngine) throws {}
  func release() {}
}

final class FakePlatform: RecorderPlatform {
  var supportedEncoders: Set<String> = ["aacLc", "pcm16bits", "wav"]

  let fakeDevices = FakeDeviceRegistry()
  let fakeEnvironment = FakeAudioEnvironment()

  var devices: DeviceRegistry { fakeDevices }
  var environment: AudioEnvironment { fakeEnvironment }
  let inputRoute: InputRoute = FakeInputRoute()

  private(set) var engines: [FakeCaptureEngine] = []
  private(set) var fileEngineCount = 0
  private(set) var streamEngineCount = 0

  // Lets a test set an engine up before the controller starts it.
  var prepareEngine: ((FakeCaptureEngine) -> Void)?

  var lastEngine: FakeCaptureEngine? { engines.last }

  func makeEngine(
    config: RecordConfig,
    target: CaptureTarget,
    onEvent: @escaping (CaptureEvent) -> Void
  ) -> CaptureEngine {
    switch target {
    case .file: fileEngineCount += 1
    case .stream: streamEngineCount += 1
    }

    let engine = FakeCaptureEngine(config: config, onEvent: onEvent)
    prepareEngine?(engine)
    engines.append(engine)
    return engine
  }
}

final class RecordingSink: RecorderSink {
  private(set) var states: [RecordState] = []
  private(set) var chunks: [Data] = []
  private(set) var configs: [RecordConfig] = []
  private(set) var errors: [Error] = []

  func onState(_ state: RecordState) { states.append(state) }
  func onChunk(_ data: Data) { chunks.append(data) }
  func onConfigChanged(_ config: RecordConfig) { configs.append(config) }
  func onError(_ error: Error) { errors.append(error) }
}

// Wires a controller the way the channel does, and keeps every call on its queue.
final class ControllerHarness {
  let queue = DispatchQueue(label: "com.record.test")
  let platform = FakePlatform()
  let sink = RecordingSink()
  let controller: RecorderController

  init() {
    controller = RecorderController(queue: queue, platform: platform, sink: sink)
  }

  @discardableResult
  func run<T>(_ block: () throws -> T) rethrows -> T {
    try queue.sync(execute: block)
  }

  // Waits for what the controller queued for itself after an event.
  func drain() { queue.sync {} }

  func startRecording(_ config: RecordConfig = makeConfig()) throws {
    try run { try controller.start(config: config, path: "/tmp/take.m4a") }
  }
}

enum TestError: Error {
  case boom
}
