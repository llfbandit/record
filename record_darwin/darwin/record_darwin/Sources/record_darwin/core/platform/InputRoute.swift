import Foundation

// Which input a take captures from. One per recorder.
protocol InputRoute: AnyObject {
  // Binds the device with this UID before a new input opens. Nil is the default input.
  // Returns the UID it bound, nil if unknown. Throws RecorderError.noInputDevice if the device is not there.
  func bind(_ deviceId: String?, channels: Int) throws -> String?

  // Whether capture is on this device now. Nil when the route cannot tell.
  func captures(from uid: String) -> Bool?

  // Undoes what bind() left on the system. The take is over.
  func release()
}
