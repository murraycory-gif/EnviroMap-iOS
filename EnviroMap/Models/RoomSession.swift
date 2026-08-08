import Foundation

/// Metadata for a saved RoomPlan scan (mesh lives as USDZ on disk).
struct RoomSession: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    /// Relative filename under Application Support / Scans / {id}/
    var usdzFileName: String
    var wallCount: Int
    var objectCount: Int
    var doorCount: Int
    var windowCount: Int
    var thumbnailFileName: String?

    var folderName: String { id.uuidString }

    static func makeNew(name: String) -> RoomSession {
        let id = UUID()
        let now = Date()
        return RoomSession(
            id: id,
            name: name,
            notes: "",
            createdAt: now,
            updatedAt: now,
            usdzFileName: "room.usdz",
            wallCount: 0,
            objectCount: 0,
            doorCount: 0,
            windowCount: 0,
            thumbnailFileName: "thumb.jpg"
        )
    }
}

struct ScanStats: Equatable {
    var walls: Int
    var objects: Int
    var doors: Int
    var windows: Int
}
