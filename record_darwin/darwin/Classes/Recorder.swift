// https://developer.apple.com/documentation/avfoundation/avcapturedevice/microphonemode?changes=latest_beta
// https://stackoverflow.com/questions/51209310/save-avcapturevideodataoutput-to-movie-file-using-avassetwriter-in-swift
// https://developer.apple.com/documentation/avfoundation/avcaptureaudiodataoutput
// https://developer.apple.com/documentation/avfaudio/avaudioinputnode/3152102-voiceprocessingagcenabled?language=objc
// https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions
import Foundation
import AVFoundation

enum RecorderError: Error {
  case error(message: String, details: String?)
}

fileprivate enum RecordState: Int {
  case pause = 0
  case record = 1
  case stop = 2
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
  
  func dispose() {
    stopRecording()
  }
  
  func start(config: RecordConfig, path: String) throws {
    stopRecording()
    
    try deleteFile(path: path)
    
    if !isEncoderSupported(config.encoder) {
      throw RecorderError.error(message: "Failed to start recording", details: "\(config.encoder) not supported.")
    }
    
    let dev = try getRecordingInputDevice(config: config)
    
    let result = try createRecordingSession(config, dev: dev)
    
    let writer = try createWriter(config: config, path: path)

    // start recording
    DispatchQueue.global(qos: .background).async {
      writer.startWriting()
      result.session.startRunning()

      self.m_config = config
      self.m_dev = dev
      self.m_path = path
      self.updateState(RecordState.record)
    }
  }
  
  func startStream(config: RecordConfig) throws {
    stopRecording()
    
    if config.encoder != AudioEncoder.pcm16bits.rawValue {
      throw RecorderError.error(message: "Failed to start recording", details: "\(config.encoder) not supported in streaming mode.")
    }
    
    let dev = try getRecordingInputDevice(config: config)
    
    let result = try createRecordingSession(config, dev: dev)
    
    // start recording
    DispatchQueue.global(qos: .background).async {
      result.session.startRunning()

      self.m_config = config
      self.m_dev = dev
      self.updateState(RecordState.record)
    }
  }
  
  func stop() -> String? {
    let path = m_path
    
    stopRecording()
    
    return path
  }
  
  func pause() {
    if m_state == .record {
      updateState(RecordState.pause)
      m_dev?.ports.forEach({ port in port.isEnabled = false })
      m_hasBeenPaused = true
    }
  }
  
  func resume() {
    if isPaused() {
      m_dev?.ports.forEach({ port in port.isEnabled = true })
      updateState(RecordState.record)
    }
  }
  
  func isPaused() -> Bool {
    return m_state == .pause
  }
  
  func isRecording() -> Bool {
    return m_state != .stop
  }
  
  func listInputDevices() -> [AVCaptureDevice] {
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInMicrophone],
      mediaType: .audio, position: .unspecified
    )
    
    return discoverySession.devices
  }
  
  func getAmplitude() -> [String : Float] {
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
    m_writerInput?.markAsFinished()

    if let audioWriter = m_audioWriter {
      audioWriter.finishWriting(completionHandler: { [weak self] in
        self?._reset()
        self?.updateState(RecordState.stop)
      })
    } else {
      _reset()
      updateState(RecordState.stop)
    }
  }

  private func _reset() {
    m_writerInput = nil
    m_audioWriter = nil
    
    m_audioOutput?.setSampleBufferDelegate(nil, queue: nil)
    m_audioOutput = nil
    
    m_audioSession?.stopRunning()
    m_audioSession = nil
    
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
    
    // Add input
    if !session.canAddInput(dev) {
      throw RecorderError.error(message: "Failed to start recording", details: "Input device cannot be added to the capture session.")
    }
    session.addInput(dev)
    
    // Configure output settings
    let audioOut = AVCaptureAudioDataOutput()
    
#if os(iOS)
    try initAVAudioSession(config: config)
#else
    audioOut.audioSettings = getInputSettings(config: config)
#endif

    // Add output
    let audioCaptureQueue = DispatchQueue(label: "com.llfbandit.record.queue", attributes: [])
    audioOut.setSampleBufferDelegate(self, queue: audioCaptureQueue)
    guard session.canAddOutput(audioOut) else {
      throw RecorderError.error(message: "Failed to start recording", details: "AVCaptureAudioDataOutput cannot be added to the capture session.")
    }
    session.addOutput(audioOut)
    
    session.commitConfiguration()
    
    m_audioSession = session
    m_audioOutput = audioOut
    
    return (session, audioOut)
  }
  
  private func getRecordingInputDevice(config: RecordConfig) throws -> AVCaptureDeviceInput {
    guard let dev = getInputDevice(device: config.device) else {
      throw RecorderError.error(message: "Failed to start recording", details: "Input device not found.")
    }
    
    do {
      return try AVCaptureDeviceInput(device: dev)
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: error.localizedDescription)
    }
  }
  
  private func createWriter(config: RecordConfig, path: String) throws -> AVAssetWriter {
    var writer: AVAssetWriter
    let pathUrl = URL(fileURLWithPath: path)
    
    let settings = try getOutputSettings(config: config)
    
    do {
      writer = try AVAssetWriter(url: pathUrl, fileType: getFileTypeFromSettings(settings))
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: error.localizedDescription)
    }
    
    if !writer.canApply(outputSettings: settings, forMediaType: AVMediaType.audio) {
      throw RecorderError.error(message: "Failed to start recording", details: "Output format cannot be handled by the selected container.")
    }
    
    let writerInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings)
    if !writer.canAdd(writerInput) {
      throw RecorderError.error(message: "Failed to start recording", details: "Output format cannot be added to the capture session.")
    }
    writer.add(writerInput)
    
    m_audioWriter = writer
    m_writerInput = writerInput
    
    return writer
  }
  
  func deleteFile(path: String) throws {
    do {
      let fileManager = FileManager.default
      
      if fileManager.fileExists(atPath: path) {
        try fileManager.removeItem(atPath: path)
      }
    } catch {
      throw RecorderError.error(message: "Failed to start recording", details: error.localizedDescription)
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
      writeToStream(sampleBuffer, numChannels: connection.audioChannels.count)
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
  
  private func writeToStream(_ sampleBuffer: CMSampleBuffer, numChannels: Int) {
    guard let eventSink = m_recordEventHandler.eventSink else {
      return
    }

    if #available(macOS 10.15, iOS 13.0, *) {
      do {
        guard let data = try sampleBuffer.dataBuffer?.dataBytes() else {
          return
        }

        if !data.isEmpty {
          eventSink(FlutterStandardTypedData(bytes: data))
        }
      } catch {
        print(error)
        _ = stop()
      }
    } else {
      // Fallback on earlier versions
      let audioBuffer = AudioBuffer(mNumberChannels: UInt32(numChannels), mDataByteSize: 0, mData: nil)
      var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
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
