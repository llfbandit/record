import XCTest

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

@testable import record_darwin

final class ChannelSinkTests: XCTestCase {
  // Both streams in the order Dart gets them.
  private var events = [(stream: String, event: Any?)]()
  private var sink: ChannelSink!

  override func setUp() {
    super.setUp()
    makeSink()
  }

  // Every end of take closes the byte stream, the ones from the platform too.
  func testEachStopEndsTheByteStream() {
    for reason in [StopReason.stop, .routeChange, .interruption, .error] {
      makeSink()

      sink.onChunk(Data([1, 2]))
      sink.onStopped(RecordStop(reason, path: nil))
      drainMain()

      XCTAssertEqual(events.map(\.stream), ["records", "state", "records"], "\(reason)")
      XCTAssertEqual((events[0].event as? FlutterStandardTypedData)?.data, Data([1, 2]), "\(reason)")
      XCTAssertEqual((events[1].event as? [String: Any])?["reason"] as? String, reason.rawValue, "\(reason)")
      XCTAssertTrue((events[2].event as? NSObject) === FlutterEndOfEventStream, "\(reason)")
    }
  }

  // The stream is closed, so a later stop or chunk does not reach it.
  func testAClosedByteStreamGetsNothingMore() {
    sink.onStopped(RecordStop(.error, path: nil))
    drainMain()
    events = []

    sink.onChunk(Data([1, 2]))
    sink.onStopped(RecordStop(.stop, path: nil))
    drainMain()

    XCTAssertEqual(events.map(\.stream), ["state"])
  }

  private func makeSink() {
    events = []

    let state = EventStreamHandler()
    _ = state.onListen(withArguments: nil) { [unowned self] in self.events.append(("state", $0)) }
    let records = EventStreamHandler()
    _ = records.onListen(withArguments: nil) { [unowned self] in self.events.append(("records", $0)) }

    sink = ChannelSink(
      state: state,
      records: records,
      configChanged: FlutterMethodChannel(name: "test", binaryMessenger: NullMessenger())
    )
  }

  private func drainMain() {
    let done = expectation(description: "main")
    DispatchQueue.main.async { done.fulfill() }
    wait(for: [done], timeout: 1)
  }
}

// The config channel needs a messenger. These tests send nothing on it.
private final class NullMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply? = nil) {}

  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil
  ) -> FlutterBinaryMessengerConnection { 0 }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
