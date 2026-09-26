import XCTest

@testable import record_darwin

final class RecordFileTests: XCTestCase {
  private var path = ""

  override func setUp() {
    super.setUp()
    path = NSTemporaryDirectory() + "record-test-\(UUID().uuidString).tmp"
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: path)
    super.tearDown()
  }

  func testDeleteRemovesTheFile() throws {
    FileManager.default.createFile(atPath: path, contents: Data([1, 2, 3]))

    try RecordFile.delete(at: path)

    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
  }

  // start() deletes the old file first, and often there is none.
  func testDeletingAMissingFileIsNotAnError() {
    XCTAssertNoThrow(try RecordFile.delete(at: path))
    XCTAssertNoThrow(try RecordFile.delete(at: path))
  }
}
