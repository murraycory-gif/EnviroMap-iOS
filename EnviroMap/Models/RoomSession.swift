import Foundation

/// Metadata for a saved scan (structure USDZ + optional dense LiDAR mesh).
struct RoomSession: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    /// RoomPlan structure export (walls / doors / openings)
    var usdzFileName: String
    /// Dense LiDAR mesh with surface colors (full space), if available
    var denseMeshFileName: String?
    var wallCount: Int
    var objectCount: Int
    var doorCount: Int
    var windowCount: Int
    var thumbnailFileName: String?
    /// True when dense mesh was saved (everything LiDAR saw)
    var hasDenseMesh: Bool

    var folderName: String { id.uuidString }

    nonisolated static func makeNew(name: String) -> RoomSession {
        let id = UUID()
        let now = Date()
        return RoomSession(
            id: id,
            name: name,
            notes: "",
            createdAt: now,
            updatedAt: now,
            usdzFileName: "room.usdz",
            denseMeshFileName: nil,
            wallCount: 0,
            objectCount: 0,
            doorCount: 0,
            windowCount: 0,
            thumbnailFileName: "thumb.jpg",
            hasDenseMesh: false
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, notes, createdAt, updatedAt
        case usdzFileName, denseMeshFileName
        case wallCount, objectCount, doorCount, windowCount
        case thumbnailFileName, hasDenseMesh
    }

    init(
        id: UUID, name: String, notes: String,
        createdAt: Date, updatedAt: Date,
        usdzFileName: String, denseMeshFileName: String? = nil,
        wallCount: Int, objectCount: Int, doorCount: Int, windowCount: Int,
        thumbnailFileName: String?, hasDenseMesh: Bool = false
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.usdzFileName = usdzFileName
        self.denseMeshFileName = denseMeshFileName
        self.wallCount = wallCount
        self.objectCount = objectCount
        self.doorCount = doorCount
        self.windowCount = windowCount
        self.thumbnailFileName = thumbnailFileName
        self.hasDenseMesh = hasDenseMesh
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        usdzFileName = try c.decode(String.self, forKey: .usdzFileName)
        denseMeshFileName = try c.decodeIfPresent(String.self, forKey: .denseMeshFileName)
        wallCount = try c.decodeIfPresent(Int.self, forKey: .wallCount) ?? 0
        objectCount = try c.decodeIfPresent(Int.self, forKey: .objectCount) ?? 0
        doorCount = try c.decodeIfPresent(Int.self, forKey: .doorCount) ?? 0
        windowCount = try c.decodeIfPresent(Int.self, forKey: .windowCount) ?? 0
        thumbnailFileName = try c.decodeIfPresent(String.self, forKey: .thumbnailFileName)
        hasDenseMesh = try c.decodeIfPresent(Bool.self, forKey: .hasDenseMesh) ?? (denseMeshFileName != nil)
    }
}

struct ScanStats: Equatable {
    var walls: Int
    var objects: Int
    var doors: Int
    var windows: Int
}
