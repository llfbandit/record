import AVFoundation
import Foundation
import Flutter

class RecorderStreamDelegate: NSObject, AudioRecordingStreamDelegate {
  var config: RecordConfig?

  private var m_audioEngine: AVAudioEngine?
  private var m_amplitude: Float = -160.0
  private let m_bus = 0
  private var m_onRecord: () -> ()
  private var m_onPause: () -> ()
  private var m_onStop: () -> ()
  private let m_manageAudioSession: Bool

  private var m_audioEncoder: AudioEnc?
  private var m_outputFormat: AVAudioFormat?

  // Retained so that the tap can be reinstalled after an AVAudioEngine
  // configuration change (route change from plug/unplug of an external mic).
  private var m_recordEventHandler: RecordStreamHandler?
  private var m_configurationChangeObserver: NSObjectProtocol?

  init(manageAudioSession: Bool, onRecord: @escaping () -> (), onPause: @escaping () -> (), onStop: @escaping () -> ()) {
    m_manageAudioSession = manageAudioSession
    m_onRecord = onRecord
    m_onPause = onPause
    m_onStop = onStop
  }

  func start(config: RecordConfig, recordEventHandler: RecordStreamHandler) throws {
    let audioEngine = AVAudioEngine()

    try initAVAudioSession(config: config, manageAudioSession: m_manageAudioSession)
    try setVoiceProcessing(echoCancel: config.echoCancel, autoGain: config.autoGain, audioEngine: audioEngine)

    m_outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(config.sampleRate),
      channels: AVAudioChannelCount(config.numChannels),
      interleaved: true
    )

    guard m_outputFormat != nil else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format is not supported: \(config.sampleRate)Hz - \(config.numChannels) channels."
      )
    }

    self.m_audioEngine = audioEngine
    self.config = config
    self.m_recordEventHandler = recordEventHandler

    try installInputTap(bufferSize: AVAudioFrameCount(config.streamBufferSize ?? 1024))

    audioEngine.prepare()
    try audioEngine.start()

    // Observe engine configuration changes (fired when the audio I/O route
    // changes mid-session, e.g. user plugs in or unplugs a USB/Lightning mic).
    // Without this, the engine gets stopped by the system and our tap goes
    // silent until the recorder is fully restarted by the host app.
    m_configurationChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: audioEngine,
      queue: nil) { [weak self] _ in
        self?.handleConfigurationChange()
      }

    m_onRecord()
  }

  // Reinstall the tap on the input node using the current input format and a
  // fresh AVAudioConverter. Safe to call both on initial start and from the
  // configuration change handler; the caller must ensure any existing tap has
  // been removed first when appropriate.
  private func installInputTap(bufferSize: AVAudioFrameCount) throws {
    guard let audioEngine = m_audioEngine, let dstFormat = m_outputFormat else {
      return
    }

    // Re-read the current input format. After a route change the inputNode
    // is lazily recreated against the new hardware, so this reflects the
    // connected device's native sample rate and channel count.
    let srcFormat = audioEngine.inputNode.inputFormat(forBus: 0)

    guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
      throw RecorderError.error(
        message: "Failed to start recording",
        details: "Format conversion is not possible."
      )
    }
    converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue

    audioEngine.inputNode.installTap(
      onBus: m_bus,
      bufferSize: bufferSize,
      format: srcFormat) { [weak self] (buffer, _) -> Void in
        guard let self = self, let handler = self.m_recordEventHandler else {
          return
        }
        self.stream(
          buffer: buffer,
          dstFormat: dstFormat,
          converter: converter,
          recordEventHandler: handler
        )
      }
  }

  private func handleConfigurationChange() {
    // Per Apple: when the engine's I/O unit observes a change to the input or
    // output hardware's channel count or sample rate, the engine stops itself
    // and uninitializes. The tap installed against the old inputNode is gone.
    // We must re-tap the (recreated) inputNode with its new input format and
    // a fresh converter, then start the engine again.
    guard let audioEngine = m_audioEngine, let config = config else { return }

    do {
      audioEngine.inputNode.removeTap(onBus: m_bus)
      try installInputTap(bufferSize: AVAudioFrameCount(config.streamBufferSize ?? 1024))
      if !audioEngine.isRunning {
        try audioEngine.start()
      }
    } catch {
      print("[record_ios] Failed to handle configuration change: \(error)")
    }
  }

  func stop(completionHandler: @escaping (String?) -> ()) {
    if let observer = m_configurationChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      m_configurationChangeObserver = nil
    }

    if let audioEngine = m_audioEngine {
      do {
        try setVoiceProcessing(echoCancel: false, autoGain: false, audioEngine: audioEngine)
      } catch {}
    }

    m_audioEngine?.inputNode.removeTap(onBus: m_bus)
    m_audioEngine?.stop()
    m_audioEngine = nil
    m_recordEventHandler = nil

    if let encoder = m_audioEncoder {
      encoder.dispose()
      m_audioEncoder = nil
    }
    m_outputFormat = nil

    completionHandler(nil)
    m_onStop()

    config = nil
  }
  
  func pause() {
    m_audioEngine?.pause()
    m_onPause()
  }

  func resume() throws {
    try m_audioEngine?.start()
    m_onRecord()
  }
  
  func cancel() throws {
    stop { path in }
  }
  
  func getAmplitude() -> Float {
    return m_amplitude
  }
  
  func dispose() {
    stop { path in }
  }
  
  // Set up AGC & echo cancel
  private func setVoiceProcessing(echoCancel: Bool, autoGain: Bool, audioEngine: AVAudioEngine) throws {
    if #available(iOS 13.0, *) {
      do {
        try audioEngine.inputNode.setVoiceProcessingEnabled(echoCancel)
        audioEngine.inputNode.isVoiceProcessingAGCEnabled = autoGain
      } catch {
        throw RecorderError.error(
          message: "Failed to setup voice processing",
          details: "Echo cancel error: \(error)"
        )
      }
    }
  }

  private func updateAmplitudeInt16(buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.int16ChannelData else {
      return
    }

    let frameCount = Int(buffer.frameLength)
    let firstChannelPointer = channelData[0]
    var maxSample: Float = -160.0

    for i in 0..<frameCount {
      let curSample = abs(Float(firstChannelPointer[i]))
      if curSample > maxSample {
        maxSample = curSample
      }
    }

    m_amplitude = 20 * (log(maxSample / 32767.0) / log(10))
  }
  
  private func stream(
    buffer: AVAudioPCMBuffer,
    dstFormat: AVAudioFormat,
    converter: AVAudioConverter,
    recordEventHandler: RecordStreamHandler
  ) -> Void {

    guard let convertedBuffer = convertBuffer(buffer: buffer, dstFormat: dstFormat, converter: converter) else {
      stop { path in }
      return
    }

    updateAmplitudeInt16(buffer: convertedBuffer)

    if config?.encoder == AudioEncoder.aacLc.rawValue {
      guard let dataList = encodeAac(buffer: convertedBuffer) else {
        stop { path in }
        return
      }

      sendBytes(dataList: dataList, recordEventHandler: recordEventHandler)
    } else if config?.encoder == AudioEncoder.pcm16bits.rawValue {
      if let data = convertInt16toUInt8(buffer: convertedBuffer) {
        sendBytes(dataList: [data], recordEventHandler: recordEventHandler)
      }
    }
  }
  
  private func sendBytes(dataList: [Data], recordEventHandler: RecordStreamHandler) {
    // Send bytes
    if let eventSink = recordEventHandler.eventSink {
      for data in dataList {
        DispatchQueue.main.async {
          eventSink(FlutterStandardTypedData(bytes: data))
        }
      }
    }
  }
  
  private func convertBuffer(
    buffer: AVAudioPCMBuffer,
    dstFormat: AVAudioFormat,
    converter: AVAudioConverter) -> AVAudioPCMBuffer? {

    let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }
    
    // Determine frame capacity
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * dstFormat.sampleRate / buffer.format.sampleRate)
    
    // Destination buffer
    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: capacity) else {
      print("Unable to create output buffer")
      return nil
    }
    
    // Convert input buffer (resample, num channels)
    var error: NSError? = nil
    converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputCallback)
    if error != nil {
      print("Unable to convert input buffer \(error!)")
      return nil
    }
      
    return convertedBuffer
  }
  
  private func encodeAac(buffer: AVAudioPCMBuffer) -> [Data]? {
    // Lazily initialize AAC encoder
    if m_audioEncoder == nil {
      m_audioEncoder = AacAdtsEncoder()
      do {
        try m_audioEncoder!.setup(config: config!, format: m_outputFormat!)
      } catch {
        print("Failed to setup AAC encoder: \(error)")
        return nil
      }
    }

    guard let encoder = m_audioEncoder else {
      return nil
    }

    return encoder.encode(buffer: buffer)
  }
  
  // Little endian
  private func convertInt16toUInt8(buffer: AVAudioPCMBuffer) -> Data? {
    guard let channelData = buffer.int16ChannelData else {
      return nil
    }
    
    let frameCount = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    
    var bytes = Data(capacity: frameCount * channels * 2)
    for frame in 0..<frameCount {
      for ch in 0..<channels {
        let sample = channelData[ch][frame]
        bytes.append(UInt8(sample & 0x00FF))
        bytes.append(UInt8((sample >> 8) & 0x00FF))
      }
    }
    
    return bytes
  }
}
