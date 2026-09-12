import Flutter

public class StateStreamHandler: NSObject, FlutterStreamHandler {
  private var m_eventSink: FlutterEventSink?
  private let m_lock = NSLock()

  var eventSink: FlutterEventSink? { m_lock.withLock { m_eventSink } }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    m_lock.withLock { m_eventSink = events }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    m_lock.withLock { m_eventSink = nil }
    return nil
  }
}

public class RecordStreamHandler: NSObject, FlutterStreamHandler {
  private var m_eventSink: FlutterEventSink?
  private let m_lock = NSLock()

  var eventSink: FlutterEventSink? { m_lock.withLock { m_eventSink } }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    m_lock.withLock { m_eventSink = events }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    m_lock.withLock { m_eventSink = nil }
    return nil
  }
}
