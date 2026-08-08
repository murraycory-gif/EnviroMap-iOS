import XCTest
@testable import EnviroMap

final class RoomSessionTests: XCTestCase {
    func testMakeNewHasStableDefaults() {
        let session = RoomSession.makeNew(name: "Living Room")
        XCTAssertEqual(session.name, "Living Room")
        XCTAssertEqual(session.usdzFileName, "room.usdz")
        XCTAssertEqual(session.wallCount, 0)
        XCTAssertEqual(session.objectCount, 0)
        XCTAssertEqual(session.doorCount, 0)
        XCTAssertEqual(session.windowCount, 0)
        XCTAssertFalse(session.folderName.isEmpty)
        XCTAssertEqual(session.folderName, session.id.uuidString)
    }

    func testSessionCodableRoundTrip() throws {
        let original = RoomSession.makeNew(name: "Kitchen")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoomSession.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testScanStatsEquality() {
        let a = ScanStats(walls: 4, objects: 2, doors: 1, windows: 2)
        let b = ScanStats(walls: 4, objects: 2, doors: 1, windows: 2)
        XCTAssertEqual(a, b)
    }
}
