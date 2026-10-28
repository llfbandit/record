import Foundation

// Follows the input of one take, across its inputs: which one it is, and if it is still there.
final class InputTracker {
  private let m_route: InputRoute
  private let m_devices: DeviceRegistry
  private var m_unwatchDevices: (() -> Void)?

  // The input in use. When it is gone, the route is lost.
  private(set) var uid: String?

  // Watches the devices until release(): a device can go without the input telling us.
  // onChange comes from any thread.
  init(route: InputRoute, devices: DeviceRegistry, onChange: @escaping () -> Void) {
    m_route = route
    m_devices = devices
    m_unwatchDevices = devices.watch(onChange)
  }

  // Binds the device before a new input opens. Nil is the default input. It becomes the input in use.
  func bind(_ deviceId: String?, channels: Int) throws -> String? {
    uid = try m_route.bind(deviceId, channels: channels)
    return uid
  }

  // False when the input in use is gone. When unsure, true.
  var isAvailable: Bool {
    uid.map(m_devices.isAvailable) ?? true
  }

  // The take is over.
  func release() {
    m_unwatchDevices?()
    m_unwatchDevices = nil
    m_route.release()
  }
}
