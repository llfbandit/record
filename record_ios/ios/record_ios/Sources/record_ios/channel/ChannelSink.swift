import Flutter
import Foundation

// Sends the output of one recorder back to Dart, on the main thread.
final class ChannelSink: RecorderSink {
  private let m_state: StateStreamHandler
  private let m_records: RecordStreamHandler
  private let m_configChanged: FlutterMethodChannel

  init(state: StateStreamHandler, records: RecordStreamHandler, configChanged: FlutterMethodChannel) {
    m_state = state
    m_records = records
    m_configChanged = configChanged
  }

  func onState(_ state: RecordState) {
    guard let sink = m_state.eventSink else { return }

    DispatchQueue.main.async { sink(state.rawValue) }
  }

  func onChunk(_ data: Data) {
    guard let sink = m_records.eventSink else { return }

    DispatchQueue.main.async { sink(FlutterStandardTypedData(bytes: data)) }
  }

  func onConfigChanged(_ config: RecordConfig) {
    let args = config.toMap()

    DispatchQueue.main.async { [weak self] in
      self?.m_configChanged.invokeMethod("onConfigChanged", arguments: args)
    }
  }

  // Dart does not listen to an error during a take yet.
  func onError(_ error: Error) {
    print("record: \(error)")
  }
}
