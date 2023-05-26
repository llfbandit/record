// https://developer.apple.com/documentation/avfoundation/avcapturedevice/microphonemode?changes=latest_beta
// https://stackoverflow.com/questions/51209310/save-avcapturevideodataoutput-to-movie-file-using-avassetwriter-in-swift
// https://developer.apple.com/documentation/avfoundation/avcaptureaudiodataoutput
// https://developer.apple.com/documentation/avfaudio/avaudioinputnode/3152102-voiceprocessingagcenabled?language=objc
// https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions
import Foundation
import AVFoundation

enum RecorderError: Error {
  case start(message: String, details: String?)
}

fileprivate enum RecordState: Int {
  case pause = 0
  case record = 1
  case stop = 2
}

class RecordConfig {
  let encoder: String
  let bitRate: Int
  let samplingRate: Int
  let numChannels: Int
  let device: [String: Any]?
  let autoGain: Bool
  let echoCancel: Bool
  let noiseCancel: Bool

  init(encoder: String,
       bitRate: Int,
       samplingRate: Int,
       numChannels: Int,
       device: [String : Any]? = nil,
       autoGain: Bool = false,
       echoCancel: Bool = false,
       noiseCancel: Bool = false
  ) {
    self.encoder = encoder
    self.bitRate = bitRate
    self.samplingRate = samplingRate
    self.numChannels = numChannels
    self.device = device
    self.autoGain = autoGain
    self.echoCancel = echoCancel
    self.noiseCancel = noiseCancel
  }
}

class Recorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
  private var m_audioSession: AVCaptureSession?
  private var m_audioOutput: AVCaptureAudioDataOutput?
  private var m_audioWriter: AVAssetWriter?
  private var m_writerInput: AVAssetWriterInput?
  private var m_dev: AVCaptureInput?
  private var m_path: String?
  private var m_maxAmplitude: Float = -160.0
  private var m_startPts: CMTime?
  private var m_lastPts: CMTime = CMTimeMake(value: 0, timescale: 0)
  private var m_state: RecordState = RecordState.stop
  private var m_hasBeenPaused: Bool = false
  private var m_config: RecordConfig?
  
  private var m_stateEventHandler: StateStreamHandler
  private var m_recordEventHandler: RecordStreamHandler
  
  init(stateEventHandler: StateStreamHandler, recordEventHandler: RecordStreamHandler) {
    m_stateEventHandler = stateEventHandler
    m_recordEventHandler = recordEventHandler
  }
  
  public func dispose() {
    stopRecording()
  }
  
  public func start(config: RecordConfig, path: String) throws {
    stopRecording()

    try deleteFile(path: path)

    let dev = try getRecordingInputDevice(config: config)
    
    let result = try createRecordingSession(config, dev: dev)

    let writer = try createWriter(config: config, path: path)
    
    // start recording
    writer.startWriting()
    result.session.startRunning()

    m_config = config
    m_dev = dev
    m_path = path
    updateState(RecordState.record)
  }
  
  public func startStream(config: RecordConfig) throws {
    stopRecording()
    
    let dev = try getRecordingInputDevice(config: config)
    
    let result = try createRecordingSession(config, dev: dev)
    
    // start recording
    result.session.startRunning()

    m_config = config
    m_dev = dev
    updateState(RecordState.record)
  }
  
  public func stop() -> String? {
    let path = m_path
    
    stopRecording()
    updateState(RecordState.stop)
    
    return path
  }
  
  public func pause() {
    if m_state == .record {
      updateState(RecordState.pause)
      m_dev?.ports.forEach({ port in port.isEnabled = false })
      m_hasBeenPaused = true
    }
  }
  
  public func resume() throws {
    if isPaused() {
      m_dev?.ports.forEach({ port in port.isEnabled = true })
      updateState(RecordState.record)
    }
  }
  
  public func isPaused() -> Bool {
    return m_state == .pause
  }
  
  public func isRecording() -> Bool {
    return m_state != .stop
  }
  
  public func listInputDevices() -> [AVCaptureDevice] {
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInMicrophone],
      mediaType: .audio, position: .unspecified
    )
    
    return discoverySession.devices
  }
  
  public func isEncoderSupported(_ encoder: String) -> Bool {
    let encoderSettings = getEncoderSettings(encoder)
    return encoderSettings != nil
  }
  
  public func getAmplitude() -> [String : Float] {
    var amp = ["current" : -160.0, "max" : -160.0] as [String : Float]
    
    if let audioOutput = m_audioOutput {
      let current = audioOutput.connections.first?.audioChannels.first?.averagePowerLevel
      if let current = current {
        if (current > m_maxAmplitude) {
          m_maxAmplitude = current
        }
        
        amp["current"] = min(0.0, max(current, -160.0))
        amp["max"] = min(0.0, max(m_maxAmplitude, -160.0))
      }
    }
    
    return amp
  }

  private func stopRecording() {
    m_audioSession?.stopRunning()
    m_audioSession = nil
    
    m_audioOutput?.setSampleBufferDelegate(nil, queue: nil)
    m_audioOutput = nil
    
    m_writerInput?.markAsFinished()
    m_writerInput = nil

    m_audioWriter?.finishWriting(completionHandler: {
      self.m_audioWriter = nil
    })
    
    m_dev = nil

    m_startPts = nil
    m_lastPts = CMTimeMake(value: 0, timescale: 0)
    m_maxAmplitude = -160.0
    m_path = nil
    m_state = .stop
    m_config = nil
  }
  
  private func createRecordingSession(
    _ config: RecordConfig,
    dev: AVCaptureDeviceInput
  ) throws -> (session: AVCaptureSession, audioOut: AVCaptureAudioDataOutput) {

    let session = AVCaptureSession()
    session.beginConfiguration()
    
    let audioOut = AVCaptureAudioDataOutput()
    
    // Configure output settings
#if os(iOS)
    // Allow manual setup
    session.automaticallyConfiguresApplicationAudioSession = false
    
    do {
      let audioSession = AVAudioSession.sharedInstance()
      
      try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
      try audioSession.setPreferredSampleRate((config.samplingRate < 48000) ? Double(config.samplingRate) : 48000.0)
      
      try audioSession.setActive(true) // Must be done before setting channels & buffer duration
      
      try audioSession.setPreferredInputNumberOfChannels((config.numChannels > 2) ? 2 : config.numChannels)
      try audioSession.setPreferredIOBufferDuration(1.0 / (audioSession.sampleRate * 2048))
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: error.localizedDescription)
    }
#else
    /*audioOut.audioSettings = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVNumberOfChannelsKey: UInt32((config.numChannels > 2) ? 2 : config.numChannels),
        AVSampleRateKey: (config.samplingRate < 48000) ? Double(config.samplingRate) : 48000.0,
        // AVLinearPCMBitDepthKey: config.encoder == "pcm8bit" ? 8 : 16,
        // AVLinearPCMIsFloatKey: false,
        // AVLinearPCMIsBigEndianKey: false,
        // AVLinearPCMIsNonInterleaved: true
    ]*/
#endif

    // Add input
    guard session.canAddInput(dev) else {
      throw RecorderError.start(message: "Failed to start recording", details: "Input device cannot be added to the capture session.")
    }
    session.addInput(dev)
  
    // Add output
    let audioCaptureQueue = DispatchQueue(label: "com.llfbandit.record.queue", attributes: [])
    audioOut.setSampleBufferDelegate(self, queue: audioCaptureQueue)
    guard session.canAddOutput(audioOut) else {
      throw RecorderError.start(message: "Failed to start recording", details: "AVCaptureAudioDataOutput cannot be added to the capture session.")
    }
    session.addOutput(audioOut)
    
    session.commitConfiguration()
    
    m_audioSession = session
    m_audioOutput = audioOut

    return (session, audioOut)
  }
  
  private func getRecordingInputDevice(config: RecordConfig) throws -> AVCaptureDeviceInput {
    guard let dev = getInputDevice(device: config.device) else {
      throw RecorderError.start(message: "Failed to start recording", details: "Input device not found.")
    }

    do {
      return try AVCaptureDeviceInput(device: dev)
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: error.localizedDescription)
    }
  }
  
  private func createWriter(config: RecordConfig, path: String) throws -> AVAssetWriter {
    var writer: AVAssetWriter
    let pathUrl = URL(fileURLWithPath: path)
    
    let settings = getSettings(config: config)
    do {
      let type = settings[AVFormatIDKey] as! Int == Int(kAudioFormatAMR) ? AVFileType.mobile3GPP : AVFileType.m4a
      writer = try AVAssetWriter(url: pathUrl, fileType: type)
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: error.localizedDescription)
    }
    let writerInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings)
    guard writer.canAdd(writerInput) else {
      throw RecorderError.start(message: "Failed to start recording", details: "Output format cannot be added to the capture session.")
    }
    writer.add(writerInput)
    
    m_audioWriter = writer
    m_writerInput = writerInput
    
    return writer
  }
  
  private func deleteFile(path: String) throws {
    do {
      let fileManager = FileManager.default
      
      if fileManager.fileExists(atPath: path) {
        try fileManager.removeItem(atPath: path)
      }
    } catch {
      throw RecorderError.start(message: "Failed to start recording", details: error.localizedDescription)
    }
  }
  
  private func getSettings(config: RecordConfig) -> [String : Any] {
    let settings = [
      AVEncoderBitRateKey: config.bitRate,
      AVSampleRateKey: config.samplingRate,
      AVNumberOfChannelsKey: config.numChannels,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ] as [String : Any]
    
    var encoderSettings = getEncoderSettings(config.encoder)
    // Defaults to ACC LD
    if (encoderSettings == nil) {
      encoderSettings = [AVFormatIDKey : Int(kAudioFormatMPEG4AAC)]
    }
    
    return settings.merging(encoderSettings!, uniquingKeysWith: { (_, last) in last })
  }
  
  // https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers
  private func getEncoderSettings(_ encoder: String) -> [String : Any]? {
    switch(encoder) {
    case "aacLc":
      return [AVFormatIDKey : Int(kAudioFormatMPEG4AAC)]
    case "aacEld":
      return [AVFormatIDKey : Int(kAudioFormatMPEG4AAC_ELD)]
    case "aacHe":
      return [AVFormatIDKey : Int(kAudioFormatMPEG4AAC_HE_V2)]
    case "amrNb":
      return [AVFormatIDKey : Int(kAudioFormatAMR)]
    case "amrWb":
      return [AVFormatIDKey : Int(kAudioFormatAMR_WB)]
    case "opus":
      return [AVFormatIDKey : Int(kAudioFormatOpus)]
    case "flac":
      return [AVFormatIDKey : Int(kAudioFormatFLAC)]
    case "pcm8bit":
      return [
        AVFormatIDKey : Int(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: 8,
      ]
    case "pcm16bit":
      return [
        AVFormatIDKey : Int(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: 16,
      ]
    default:
      return nil
    }
  }
  
  private func getInputDevice(device: [String: Any]?) -> AVCaptureDevice? {
    guard let device = device else {
      // Fallback to default device
      let defaultDevice = AVCaptureDevice.default(for: .audio)
      guard let defaultDevice = defaultDevice else {
        return nil
      }

      return defaultDevice
    }
    
    // find the given device
    let devs = listInputDevices()
    let captureDev = devs.first { dev in
      dev.uniqueID == device["id"] as! String
    }
    guard let captureDev = captureDev else {
      return nil
    }
    
    return captureDev
  }
  
  private func updateState(_ state: RecordState) {
    m_state = state
    
    if let eventSink = m_stateEventHandler.eventSink {
      eventSink(state.rawValue)
    }
  }
  
  // MARK: AVCaptureAudioDataOutputSampleBufferDelegate
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    if isPaused() {
      return
    }
    
    if m_path != nil {
      writeToFile(sampleBuffer)
    } else {
      writeToStream(sampleBuffer)
    }
  }
  
  private func writeToFile(_ sampleBuffer: CMSampleBuffer) {
    guard let writerInput = m_writerInput, let audioWriter = m_audioWriter else {
      return
    }

    if m_startPts == nil {
      // start writing session
      m_startPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      audioWriter.startSession(atSourceTime: m_startPts!)
    }
    
    // calc time adjustment after pause/resume
    var adjustedSampleBuffer: CMSampleBuffer?
    if (m_hasBeenPaused) {
      m_hasBeenPaused = false
      adjustedSampleBuffer = adjustTime(sampleBuffer, by: m_lastPts)
    } else {
      adjustedSampleBuffer = sampleBuffer
    }
    guard let adjustedSampleBuffer = adjustedSampleBuffer else {
      print("An error occured when adjusting time for audio sample")
      stopRecording()
      return
    }
    
    // record most recent time
    m_lastPts = CMSampleBufferGetPresentationTimeStamp(adjustedSampleBuffer)
    
    if writerInput.isReadyForMoreMediaData {
      writerInput.append(adjustedSampleBuffer)
    }
  }
  
  /*private func writeToStream(_ sampleBuffer: CMSampleBuffer) {
    guard let eventSink = m_recordEventHandler.eventSink else {
      return
    }
    
    /*guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
          let sampleRate = description.audioStreamBasicDescription?.mSampleRate,
          let channelsCount = description.audioStreamBasicDescription?.mChannelsPerFrame,
          let mFormatID = description.audioStreamBasicDescription?.mFormatID,
          let mBitsPerChannel = description.audioStreamBasicDescription?.mBitsPerChannel
    else {
      return
    }*/

    var audioBufferList = AudioBufferList()
    var blockBuffer: CMBlockBuffer?
    
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: &audioBufferList,
      bufferListSize: MemoryLayout<AudioBufferList>.size,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: 0,
      blockBufferOut: &blockBuffer)
    
    let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
  
    var data = Data()
    for audioBuffer in buffers {
      if let frame = audioBuffer.mData?.assumingMemoryBound(to: UInt8.self) {
        data.append(frame, count: Int(audioBuffer.mDataByteSize))
      }
    }

    if !data.isEmpty {
      eventSink(data)
    }
  }*/
  
  private func writeToStream(_ sampleBuffer: CMSampleBuffer) {
    guard let eventSink = m_recordEventHandler.eventSink else {
      return
    }
    
    guard let config = m_config else {
      return
    }

    let audioBuffer = AudioBuffer(mNumberChannels: UInt32(config.numChannels), mDataByteSize: 0, mData: nil)
    var audioBufferList = AudioBufferList(mNumberBuffers: UInt32(config.numChannels), mBuffers: audioBuffer)
    var blockBuffer: CMBlockBuffer?
    
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: &audioBufferList,
      bufferListSize: MemoryLayout<AudioBufferList>.size(ofValue: audioBufferList),
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
      blockBufferOut: &blockBuffer)
    
    guard let bufferData = audioBufferList.mBuffers.mData else {
      return
    }
    
    let data = Data(bytesNoCopy: bufferData, count: Int(audioBufferList.mBuffers.mDataByteSize), deallocator: .none)

    if !data.isEmpty {
      eventSink(FlutterStandardTypedData(bytes: data))
    }
  }
  
  private func adjustTime(_ sampleBuffer: CMSampleBuffer, by timeOffset: CMTime) -> CMSampleBuffer? {
    var itemCount: CMItemCount = 0
    var status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &itemCount)
    if status != 0 {
      print("Error when initializing timing info of sample: \(status).")
      return nil
    }
    
    var timingInfo = [CMSampleTimingInfo](
      repeating: CMSampleTimingInfo(
        duration: CMTimeMake(value: 0, timescale: 0),
        presentationTimeStamp: CMTimeMake(value: 0, timescale: 0),
        decodeTimeStamp: CMTimeMake(value: 0, timescale: 0)),
      count: itemCount
    )
    status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: itemCount, arrayToFill: &timingInfo, entriesNeededOut: &itemCount)
    if status != 0 {
      print("Error when retrieving timing info of sample: \(status).")
      return nil
    }
    
    for i in 0 ..< itemCount {
      timingInfo[i].decodeTimeStamp = timeOffset
      timingInfo[i].presentationTimeStamp = timeOffset
    }
    
    var adjustedSampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateCopyWithNewTiming(
      allocator: kCFAllocatorDefault,
      sampleBuffer: sampleBuffer,
      sampleTimingEntryCount: itemCount,
      sampleTimingArray: &timingInfo,
      sampleBufferOut: &adjustedSampleBuffer
    )
    
    return adjustedSampleBuffer
  }
}
