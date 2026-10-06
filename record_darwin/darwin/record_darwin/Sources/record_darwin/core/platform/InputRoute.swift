import AVFoundation

// Which input an engine captures from. One per recorder.
protocol InputRoute: AnyObject {
  // Points a new engine at the input with this UID, before its input node is used.
  // Nil is the default input. The channels are what the take asks for.
  func bind(_ deviceId: String?, channels: Int, to engine: AVAudioEngine) throws

  // Undoes what bind() left on the system. The take is over.
  func release()
}
