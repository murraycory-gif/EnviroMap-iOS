import Foundation
import UIKit
import RoomPlan
import SceneKit

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [RoomSession] = []
    @Published var errorMessage: String?

    private let indexFileName = "sessions.json"
    private let fileManager = FileManager.default

    private var rootURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent("EnviroMapScans", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexURL: URL {
        rootURL.appendingPathComponent(indexFileName)
    }

    init() {
        loadIndex()
    }

    func folderURL(for session: RoomSession) -> URL {
        rootURL.appendingPathComponent(session.folderName, isDirectory: true)
    }

    func usdzURL(for session: RoomSession) -> URL {
        folderURL(for: session).appendingPathComponent(session.usdzFileName)
    }

    /// Dense LiDAR mesh (full space) if saved.
    func denseMeshURL(for session: RoomSession) -> URL? {
        guard let name = session.denseMeshFileName else { return nil }
        let url = folderURL(for: session).appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Prefer full visual dense mesh; fall back to RoomPlan structure USDZ.
    func preferredMeshURL(for session: RoomSession) -> URL {
        if let dense = denseMeshURL(for: session) {
            return dense
        }
        return usdzURL(for: session)
    }

    func thumbnailURL(for session: RoomSession) -> URL? {
        guard let name = session.thumbnailFileName else { return nil }
        return folderURL(for: session).appendingPathComponent(name)
    }

    func loadIndex() {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            sessions = []
            return
        }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoded = try JSONDecoder().decode([RoomSession].self, from: data)
            sessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            errorMessage = "Could not load saved rooms: \(error.localizedDescription)"
            sessions = []
        }
    }

    private func saveIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        try data.write(to: indexURL, options: [.atomic])
    }

    /// Persist RoomPlan structure + optional dense LiDAR mesh.
    func saveCapturedRoom(
        _ room: CapturedRoom,
        name: String,
        notes: String = "",
        previewImage: UIImage? = nil,
        denseMeshExporter: ((URL) -> String?)? = nil
    ) throws -> RoomSession {
        var session = RoomSession.makeNew(name: name.isEmpty ? defaultName() : name)
        session.notes = notes
        session.wallCount = room.walls.count
        session.objectCount = room.objects.count
        session.doorCount = room.doors.count
        session.windowCount = room.windows.count

        let folder = folderURL(for: session)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        // 1) RoomPlan structure USDZ
        let usdz = folder.appendingPathComponent(session.usdzFileName)
        try room.export(to: usdz)

        // 2) Dense full-space LiDAR mesh
        if let exporter = denseMeshExporter,
           let denseName = exporter(folder) {
            session.denseMeshFileName = denseName
            session.hasDenseMesh = true
        }

        // Parametric JSON
        let metaURL = folder.appendingPathComponent("captured_room.json")
        if let encoded = try? JSONEncoder().encode(room) {
            try? encoded.write(to: metaURL, options: [.atomic])
        }

        if let image = previewImage,
           let jpeg = image.jpegData(compressionQuality: 0.75) {
            let thumbName = session.thumbnailFileName ?? "thumb.jpg"
            let thumb = folder.appendingPathComponent(thumbName)
            try jpeg.write(to: thumb, options: [.atomic])
        }

        sessions.insert(session, at: 0)
        try saveIndex()
        return session
    }


    /// File-only prepare (thread-safe). Call `commitSession` on MainActor after.
    nonisolated func prepareFullEnvironment(
        name: String,
        notes: String,
        meshFileName: String,
        sourceDirectory: URL,
        preview: UIImage?,
        meshChunkCount: Int
    ) throws -> RoomSession {
        var session = RoomSession.makeNew(name: name.isEmpty ? Self.defaultNameStatic() : name)
        session.notes = notes
        session.wallCount = 0
        session.objectCount = meshChunkCount
        session.doorCount = 0
        session.windowCount = 0
        session.hasDenseMesh = true
        session.denseMeshFileName = meshFileName
        session.usdzFileName = meshFileName

        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let root = base.appendingPathComponent("EnviroMapScans", isDirectory: true)
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let folder = root.appendingPathComponent(session.folderName, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let src = sourceDirectory.appendingPathComponent(meshFileName)
        let dest = folder.appendingPathComponent(meshFileName)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: src, to: dest)

        if let files = try? fm.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil) {
            for f in files {
                let n = f.lastPathComponent
                guard n.hasPrefix("tex_") || n == "atlas.png" || n == "color_proof.png" else { continue }
                let d = folder.appendingPathComponent(n)
                if fm.fileExists(atPath: d.path) { try? fm.removeItem(at: d) }
                try? fm.copyItem(at: f, to: d)
            }
        }

        if let image = preview, let jpeg = image.jpegData(compressionQuality: 0.75) {
            let thumbName = session.thumbnailFileName ?? "thumb.jpg"
            try jpeg.write(to: folder.appendingPathComponent(thumbName), options: [.atomic])
        }
        return session
    }

    /// Main-thread only: publish session into library index.
    func commitSession(_ session: RoomSession) throws {
        sessions.insert(session, at: 0)
        try saveIndex()
    }

    /// Convenience when already on MainActor.
    func saveFullEnvironment(
        name: String,
        notes: String,
        meshFileName: String,
        sourceDirectory: URL,
        preview: UIImage?,
        meshChunkCount: Int
    ) throws -> RoomSession {
        let session = try prepareFullEnvironment(
            name: name,
            notes: notes,
            meshFileName: meshFileName,
            sourceDirectory: sourceDirectory,
            preview: preview,
            meshChunkCount: meshChunkCount
        )
        try commitSession(session)
        return session
    }

    nonisolated private static func defaultNameStatic() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return "Scan \(f.string(from: Date()))"
    }

    func rename(_ session: RoomSession, to name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].name = name
        sessions[idx].updatedAt = Date()
        try? saveIndex()
    }

    func delete(_ session: RoomSession) {
        let folder = folderURL(for: session)
        try? fileManager.removeItem(at: folder)
        sessions.removeAll { $0.id == session.id }
        try? saveIndex()
    }

    func shareItems(for session: RoomSession) -> [Any] {
        var items: [Any] = []
        let preferred = preferredMeshURL(for: session)
        if fileManager.fileExists(atPath: preferred.path) {
            items.append(preferred)
        }
        let structure = usdzURL(for: session)
        if preferred.path != structure.path,
           fileManager.fileExists(atPath: structure.path) {
            items.append(structure)
        }
        return items
    }

    private func defaultName() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return "Scan \(f.string(from: Date()))"
    }
}
