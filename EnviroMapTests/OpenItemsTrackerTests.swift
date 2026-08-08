import XCTest

/// Ensures the open-items tracker file stays in the repo and keeps expected columns.
final class OpenItemsTrackerTests: XCTestCase {
    func testOpenItemsFileExists() {
        let root = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // EnviroMapTests
            .deletingLastPathComponent() // repo root
        let path = root.appendingPathComponent("OPEN_ITEMS.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "OPEN_ITEMS.md missing at \(path.path)")
    }

    func testOpenItemsHasRequiredHeaders() throws {
        let root = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent("OPEN_ITEMS.md")
        let text = try String(contentsOf: path, encoding: .utf8)
        for col in ["Area Of App", "Problem", "Testing Date", "Completed Date", "Status"] {
            XCTAssertTrue(text.contains(col), "Missing column: \(col)")
        }
    }
}
