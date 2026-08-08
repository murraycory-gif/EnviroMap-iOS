import Foundation
import UIKit
import RoomPlan

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [RoomSession] = []
    @Published var errorMessage: String?

    private let indexFileName = "sessions.json"
    private let fileManager = FileManager.default

    private var rootURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

    /// Persist a finished RoomPlan result to disk and library.
    func saveCapturedRoom(
        _ room: CapturedRoom,
        name: String,
        notes: String = "",
        previewImage: UIImage? = nil
    ) throws -> RoomSession {
        var session = RoomSession.makeNew(name: name.isEmpty ? defaultName() : name)
        session.notes = notes
        session.wallCount = room.walls.count
        session.objectCount = room.objects.count
        session.doorCount = room.doors.count
        session.windowCount = room.windows.count

        let folder = folderURL(for: session)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        // USDZ export (filename avoids leading-digit issues on older iOS)
        let usdz = folder.appendingPathComponent(session.usdzFileName)
        try room.export(to: usdz)

        // Optional parametric JSON (CapturedRoom is Codable)
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
        let usdz = usdzURL(for: session)
        if fileManager.fileExists(atPath: usdz.path) {
            items.append(usdz)
        }
        return items
    }

    private func defaultName() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Scan \(f.string(from: Date()))"
    }
}
