import AVFoundation

// Which input an engine captures from. One per recorder.
protocol InputRoute: AnyObject {
  // Points a new engine at the input with this UID, before its input node is used.
  // Nil is the default input. The channels are what the take asks for.
  // Returns the UID of the input it bound. Nil if unknown.
  // Throws RecorderError.noInputDevice when that input is not there: it never binds another one instead.
  func bind(_ deviceId: String?, channels: Int, to engine: AVAudioEngine) throws -> String?

  // Whether the engine captures from the input with this UID now. Nil when the route cannot tell.
  func captures(from uid: String, engine: AVAudioEngine) -> Bool?

  // Undoes what bind() left on the system. The take is over.
  func release()
}
