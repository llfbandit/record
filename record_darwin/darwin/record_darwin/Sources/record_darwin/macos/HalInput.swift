#if os(macOS)

import AVFoundation
import AudioToolbox

// Captures one input device with a HAL unit, for all macOS takes.
// AVAudioEngine can leave our input for Bluetooth buds. A HAL unit stays on the device we set.
// With echoCancel or autoGain, it is the voice processing unit. Its output must run: it plays silence.
final class HalInput: CaptureInput {
  let format: AVAudioFormat

  private let m_unit: AudioUnit
  private let m_deviceId: AudioDeviceID
  // The device format when we opened it.
  private let m_deviceFormat: AVAudioFormat
  private let m_feed: Feed
  private var m_unwatch: [() -> Void] = []
  private var m_isOpen = true

  // Element 1 of a HAL unit is its input side.
  private static let inputBus: AudioUnitElement = 1

  // A new unit on the device with this UID. See OpenInput.
  // onChange comes when the device goes, changes its format, or stops the unit.
  static func open(
    on uid: String?,
    config: RecordConfig,
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
    onChange: @escaping () -> Void
  ) throws -> HalInput {
    guard let device = uid.flatMap(CoreAudioDevices.id(forUid:)) else { throw RecorderError.noInputDevice }
    guard let deviceFormat = deviceFormat(of: device) else { throw RecorderError.noInputDevice }

    if config.usesVoiceProcessing {
      do {
        return try open(device, deviceFormat, voiceProcessing: true, config: config, onBuffer: onBuffer, onChange: onChange)
      } catch is VoiceProcessingRefused {
        // It refuses aggregate devices. Then we record without it: echoCancel and autoGain only try.
      }
    }
    return try open(device, deviceFormat, voiceProcessing: false, config: config, onBuffer: onBuffer, onChange: onChange)
  }

  private struct VoiceProcessingRefused: Error {}

  private static func open(
    _ device: AudioDeviceID,
    _ deviceFormat: AVAudioFormat,
    voiceProcessing: Bool,
    config: RecordConfig,
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
    onChange: @escaping () -> Void
  ) throws -> HalInput {
    let unit = try makeUnit(voiceProcessing ? kAudioUnitSubType_VoiceProcessingIO : kAudioUnitSubType_HALOutput)
    do {
      try setProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, inputBus, UInt32(1), "enable input")
      let format: AVAudioFormat
      if voiceProcessing {
        // Element 1 is the input. The output stays the default one.
        do {
          try setProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, inputBus, device, "set device")
        } catch {
          throw VoiceProcessingRefused()
        }
        try setProperty(unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0,
                        UInt32(config.autoGain ? 1 : 0), "set auto gain")
        let callback = AURenderCallbackStruct(inputProc: renderSilence, inputProcRefCon: nil)
        try setProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, callback, "set output callback")
        // Voice processing gives its own format.
        guard let processed = unitFormat(of: unit) else { throw RecorderError.noInputDevice }
        format = processed
      } else {
        try setProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, UInt32(0), "disable output")
        try setProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, device, "set device")
        // The input side cannot convert the rate: we take the device format as it is.
        format = deviceFormat
      }
      try setProperty(
        unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputBus, format.streamDescription.pointee, "set format")

      // A take on a stream sends a chunk about each 100 ms, unless it asks for smaller ones.
      let chunkFrames = AVAudioFrameCount(max(1, config.streamBufferSize ?? Int(format.sampleRate / 10)))
      let feed = Feed(unit: unit, format: format, chunkFrames: chunkFrames, onBuffer: onBuffer, onChange: onChange)
      let callback = AURenderCallbackStruct(inputProc: renderInput, inputProcRefCon: Unmanaged.passUnretained(feed).toOpaque())
      try setProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, callback, "set callback")
      // A render can be as big as the device buffer. Above the unit's limit (4096 by default), each render
      // would fail, and the take would record nothing.
      let unitMax = property(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, initial: UInt32(4096)) ?? 4096
      if let deviceMax = CoreAudioDevices.maxBufferFrames(of: device), deviceMax > unitMax {
        try setProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, deviceMax, "set max frames")
      }
      try check(AudioUnitInitialize(unit), "initialize")

      let maxFrames = property(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, initial: UInt32(4096))
      feed.allocate(maxFrames: maxFrames ?? 4096)

      // Voice processing opens all the mics (built-in: 1 to 3 channels). We keep that format, else the take sees a change.
      let openFormat = voiceProcessing ? Self.deviceFormat(of: device) ?? deviceFormat : deviceFormat
      return HalInput(unit: unit, deviceId: device, deviceFormat: openFormat, format: format, feed: feed)
    } catch {
      AudioComponentInstanceDispose(unit)
      throw error
    }
  }

  private init(unit: AudioUnit, deviceId: AudioDeviceID, deviceFormat: AVAudioFormat, format: AVAudioFormat, feed: Feed) {
    m_unit = unit
    m_deviceId = deviceId
    m_deviceFormat = deviceFormat
    self.format = format
    m_feed = feed

    // We listen last, so our own setup does not report a change.
    let onChange = feed.onChange
    m_unwatch = [
      CoreAudioDevices.watch(kAudioDevicePropertyDeviceIsAlive, of: deviceId, onChange),
      CoreAudioDevices.watch(kAudioDevicePropertyNominalSampleRate, of: deviceId, onChange),
      CoreAudioDevices.watch(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput, of: deviceId, onChange),
    ]
    let refCon = Unmanaged.passUnretained(feed).toOpaque()
    AudioUnitAddPropertyListener(unit, kAudioOutputUnitProperty_IsRunning, runningChanged, refCon)
  }

  deinit {
    close()
  }

  var isRunning: Bool { Self.isRunning(m_unit) }

  // The device is still there, in the format we opened it with.
  var isCurrent: Bool {
    guard let now = Self.deviceFormat(of: m_deviceId) else { return false }
    return now.hasSameLayout(as: m_deviceFormat)
  }

  func start() throws {
    m_feed.setWantsRunning(true)
    try Self.check(AudioOutputUnitStart(m_unit), "start")
  }

  func pause() {
    m_feed.setWantsRunning(false)
    AudioOutputUnitStop(m_unit)
    // Nothing renders now. The frames we hold still go to the take, so a resume does not get them late.
    m_feed.flush()
  }

  func close() {
    guard m_isOpen else { return }
    m_isOpen = false

    m_feed.setWantsRunning(false)
    m_unwatch.forEach { $0() }
    m_unwatch = []
    AudioUnitRemovePropertyListenerWithUserData(
      m_unit, kAudioOutputUnitProperty_IsRunning, runningChanged, Unmanaged.passUnretained(m_feed).toOpaque())
    AudioOutputUnitStop(m_unit)
    AudioUnitUninitialize(m_unit)

    // Nothing renders now. The last frames still go to the take, before its format may change.
    // It also waits for the queue, so no running check still uses the unit.
    m_feed.close()
    // Now, not later: a voice processing unit still there stops the next one from capturing.
    AudioComponentInstanceDispose(m_unit)
    Self.keepAlive(m_feed)
  }

  // MARK: - Internal

  // Float samples, one buffer per channel: what the take expects from an input. Nil if the device has none.
  static func format(sampleRate: Double, channels: Int) -> AVAudioFormat? {
    guard sampleRate > 0, channels > 0 else { return nil }
    if channels <= 2 { return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)) }

    guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)) else { return nil }
    return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: layout)
  }

  // MARK: - Private

  private static let closedFeeds = DispatchQueue(label: "com.record.closedFeeds")

  // A listener call can still come after we remove it, and it uses the feed.
  // If we free the feed before, the app crashes. So we keep it 3 seconds more, like EngineInput.
  private static func keepAlive(_ feed: Feed) {
    closedFeeds.asyncAfter(deadline: .now() + 3) { withExtendedLifetime(feed) {} }
  }

  private static func deviceFormat(of deviceId: AudioDeviceID) -> AVAudioFormat? {
    guard let rate = CoreAudioDevices.sampleRate(of: deviceId) else { return nil }
    return format(sampleRate: rate, channels: CoreAudioDevices.inputChannels(of: deviceId))
  }

  // What the input side of the unit gives, in our sample type.
  private static func unitFormat(of unit: AudioUnit) -> AVAudioFormat? {
    property(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputBus, initial: AudioStreamBasicDescription())
      .flatMap { format(sampleRate: $0.mSampleRate, channels: Int($0.mChannelsPerFrame)) }
  }

  fileprivate static func isRunning(_ unit: AudioUnit) -> Bool {
    (property(unit, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, initial: UInt32(0)) ?? 0) != 0
  }

  private static func makeUnit(_ subType: OSType) throws -> AudioUnit {
    var desc = AudioComponentDescription(
      componentType: kAudioUnitType_Output,
      componentSubType: subType,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0,
      componentFlagsMask: 0
    )
    guard let component = AudioComponentFindNext(nil, &desc) else { throw RecorderError.startFailed("No HAL unit.") }

    var unit: AudioUnit?
    try check(AudioComponentInstanceNew(component, &unit), "new unit")
    guard let unit else { throw RecorderError.startFailed("No HAL unit.") }
    return unit
  }

  private static func setProperty<T>(
    _ unit: AudioUnit,
    _ property: AudioUnitPropertyID,
    _ scope: AudioUnitScope,
    _ element: AudioUnitElement,
    _ value: T,
    _ call: String
  ) throws {
    var value = value
    try check(AudioUnitSetProperty(unit, property, scope, element, &value, UInt32(MemoryLayout<T>.size)), call)
  }

  // Nil when the unit does not give it.
  private static func property<T>(
    _ unit: AudioUnit,
    _ property: AudioUnitPropertyID,
    _ scope: AudioUnitScope,
    _ element: AudioUnitElement,
    initial: T
  ) -> T? {
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    return AudioUnitGetProperty(unit, property, scope, element, &value, &size) == noErr ? value : nil
  }

  private static func check(_ status: OSStatus, _ call: String) throws {
    guard status == noErr else { throw RecorderError.startFailed("HAL unit, \(call): OSStatus \(status)") }
  }
}

// What the unit's callbacks need. The render callback runs on the HAL's IO thread: it must not wait or allocate.
// So it only copies frames into a ring made before the start. A timer on the queue cuts chunks for the take.
private final class Feed {
  let unit: AudioUnit
  let format: AVAudioFormat
  let chunkFrames: AVAudioFrameCount
  let onBuffer: (AVAudioPCMBuffer) -> Void
  let onChange: () -> Void
  let queue = DispatchQueue(label: "com.record.halInput")

  // One render.
  private var m_render: AVAudioPCMBuffer?
  private var m_ring: AVAudioPCMBuffer?
  private var m_timer: DispatchSourceTimer?

  // Frames since the open. The place in the ring is the count modulo its size.
  // While the unit runs, only the IO thread uses these two.
  private var m_written: Int64 = 0
  private var m_readSeen: Int64 = 0
  // Only the queue uses this one.
  private var m_read: Int64 = 0
  // What each side tells the other. The IO thread only tries the lock.
  private let m_ringLock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
  private var m_sharedWritten: Int64 = 0
  private var m_sharedRead: Int64 = 0

  private let m_lock = NSLock()
  private var m_wantsRunning = false

  init(
    unit: AudioUnit,
    format: AVAudioFormat,
    chunkFrames: AVAudioFrameCount,
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
    onChange: @escaping () -> Void
  ) {
    self.unit = unit
    self.format = format
    self.chunkFrames = chunkFrames
    self.onBuffer = onBuffer
    self.onChange = onChange
    m_ringLock.initialize(to: os_unfair_lock())
  }

  deinit {
    m_timer?.cancel()
    m_ringLock.deinitialize(count: 1)
    m_ringLock.deallocate()
  }

  // Before the unit starts: the IO thread must not allocate.
  func allocate(maxFrames: UInt32) {
    m_render = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames)
    // About 1 s, so the queue can fall behind.
    let size = max(AVAudioFrameCount(format.sampleRate), 4 * (chunkFrames + maxFrames))
    m_ring = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: size)
    m_ring?.frameLength = size

    // Half a chunk, so a full chunk does not wait long.
    let interval = min(max(Double(chunkFrames) / format.sampleRate / 2, 0.005), 0.05)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + interval, repeating: interval)
    timer.setEventHandler { [weak self] in self?.send(flush: false) }
    timer.resume()
    m_timer = timer
  }

  func setWantsRunning(_ wants: Bool) {
    m_lock.withLock { m_wantsRunning = wants }
  }

  // On the IO thread.
  func render(
    _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ timeStamp: UnsafePointer<AudioTimeStamp>,
    _ frames: UInt32
  ) -> OSStatus {
    guard let render = m_render, let ring = m_ring, frames <= render.frameCapacity else { return noErr }

    render.frameLength = frames
    let status = AudioUnitRender(unit, flags, timeStamp, 1, frames, render.mutableAudioBufferList)
    guard status == noErr else { return status }

    // When the queue is a whole ring behind, we drop the frames instead of waiting.
    if Int64(ring.frameLength) - (m_written - m_readSeen) >= Int64(frames) {
      Self.copy(Int(frames), between: render, andRingAt: m_written, ring, toRing: true)
      m_written += Int64(frames)
    }
    if os_unfair_lock_trylock(m_ringLock) {
      m_sharedWritten = m_written
      m_readSeen = m_sharedRead
      os_unfair_lock_unlock(m_ringLock)
    }
    return noErr
  }

  // Only when the unit is stopped. Sends all the frames left to the take.
  func flush() {
    queue.sync {
      withRingLock { m_sharedWritten = m_written }
      send(flush: true)
      // The IO thread is stopped, so we can tell it here.
      m_readSeen = m_read
    }
  }

  // Only when the unit is stopped. The last frames still go to the take.
  func close() {
    m_timer?.cancel()
    flush()
  }

  // On any thread. The unit stopped: if we did not ask it, the take must know.
  // We check on the queue: close() waits for it before it frees the unit, and clears wantsRunning first.
  func runningChanged() {
    queue.async { [self] in
      guard m_lock.withLock({ m_wantsRunning }), !HalInput.isRunning(unit) else { return }
      onChange()
    }
  }

  // On the queue. Sends each full chunk, and with flush the frames left.
  private func send(flush: Bool) {
    guard let ring = m_ring else { return }

    let written = withRingLock { m_sharedWritten }
    while true {
      let available = written - m_read
      let count = available >= Int64(chunkFrames) ? Int64(chunkFrames) : flush ? available : 0
      guard count > 0, let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }

      chunk.frameLength = AVAudioFrameCount(count)
      Self.copy(Int(count), between: chunk, andRingAt: m_read, ring, toRing: false)
      m_read += count
      withRingLock { m_sharedRead = m_read }
      onBuffer(chunk)
    }
  }

  // Not on the IO thread: it waits for the lock.
  private func withRingLock<T>(_ body: () -> T) -> T {
    os_unfair_lock_lock(m_ringLock)
    defer { os_unfair_lock_unlock(m_ringLock) }
    return body()
  }

  // Copies frames between a buffer and the ring, in two parts when the ring wraps.
  private static func copy(
    _ count: Int,
    between buffer: AVAudioPCMBuffer,
    andRingAt position: Int64,
    _ ring: AVAudioPCMBuffer,
    toRing: Bool
  ) {
    guard let bufferData = buffer.floatChannelData, let ringData = ring.floatChannelData else { return }

    let size = Int(ring.frameLength)
    let start = Int(position % Int64(size))
    let first = min(count, size - start)
    for channel in 0..<Int(ring.format.channelCount) {
      let inBuffer = bufferData[channel]
      let inRing = ringData[channel]
      if toRing {
        (inRing + start).update(from: inBuffer, count: first)
        inRing.update(from: inBuffer + first, count: count - first)
      } else {
        inBuffer.update(from: inRing + start, count: first)
        (inBuffer + first).update(from: inRing, count: count - first)
      }
    }
  }
}

private let renderInput: AURenderCallback = { refCon, flags, timeStamp, _, frames, _ in
  Unmanaged<Feed>.fromOpaque(refCon).takeUnretainedValue().render(flags, timeStamp, frames)
}

// The output side of the voice processing unit: silence.
private let renderSilence: AURenderCallback = { _, flags, _, _, _, data in
  if let data {
    for buffer in UnsafeMutableAudioBufferListPointer(data) {
      if let bytes = buffer.mData { memset(bytes, 0, Int(buffer.mDataByteSize)) }
    }
  }
  flags.pointee.insert(.unitRenderAction_OutputIsSilence)
  return noErr
}

private let runningChanged: AudioUnitPropertyListenerProc = { refCon, _, _, _, _ in
  Unmanaged<Feed>.fromOpaque(refCon).takeUnretainedValue().runningChanged()
}

#endif
