#if os(macOS)

import XCTest

@testable import record_darwin

final class InputFallbackCaptureTests: XCTestCase {
  private var primary: FakeCaptureEngine!
  private var fallback: FakeCaptureEngine!
  private var fallbackCount = 0

  override func setUp() {
    super.setUp()
    primary = FakeCaptureEngine(config: makeConfig(), onEvent: { _ in })
    fallback = FakeCaptureEngine(config: makeConfig(), onEvent: { _ in })
    fallbackCount = 0
  }

  private func makeCapture() -> InputFallbackCapture {
    InputFallbackCapture(primary: primary) { [unowned self] in
      fallbackCount += 1
      return fallback
    }
  }

  func testAWorkingPrimaryNeverBuildsTheFallback() throws {
    let capture = makeCapture()

    _ = try capture.start()
    capture.pause()
    capture.stop(delete: true)

    XCTAssertEqual(fallbackCount, 0)
    XCTAssertEqual(primary.pauseCount, 1)
    XCTAssertEqual(primary.stopDeleteFlags, [true])
  }

  func testAnUnkeptInputStartsTheFallbackAndRoutesTheCallsToIt() throws {
    primary.startError = InputNotKept(reason: "swapped")
    let capture = makeCapture()

    _ = try capture.start()
    capture.pause()
    try capture.resume()
    capture.stop(delete: false)

    XCTAssertEqual(fallbackCount, 1)
    XCTAssertEqual(fallback.startCount, 1)
    XCTAssertEqual(fallback.pauseCount, 1)
    XCTAssertEqual(fallback.resumeCount, 1)
    XCTAssertEqual(fallback.stopDeleteFlags, [false])
    XCTAssertEqual(primary.pauseCount, 0)
  }

  func testAnotherErrorIsFinal() {
    primary.startError = TestError.boom
    let capture = makeCapture()

    XCTAssertThrowsError(try capture.start())
    XCTAssertEqual(fallbackCount, 0)
  }

  func testAFailedFallbackThrowsItsError() {
    primary.startError = InputNotKept(reason: "swapped")
    fallback.startError = TestError.boom
    let capture = makeCapture()

    XCTAssertThrowsError(try capture.start())
  }
}

#endif
