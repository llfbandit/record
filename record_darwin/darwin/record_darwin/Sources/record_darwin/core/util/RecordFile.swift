import Foundation

enum RecordFile {
  // A missing file is not an error.
  static func delete(at path: String) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path) else { return }

    do {
      try fileManager.removeItem(atPath: path)
    } catch {
      throw RecorderError.error(
        message: "Failed to delete previous recording",
        details: error.localizedDescription
      )
    }
  }
}
