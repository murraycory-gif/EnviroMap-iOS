import Foundation
import RoomPlan
import UIKit
import Combine
import ARKit

// MARK: - SwiftUI-facing model (no NSObject)

/// Owns scan state for SwiftUI. Real LiDAR work runs in `RoomCaptureHostController`.
final class RoomCaptureModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case processing
        case completed
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var finalRoom: CapturedRoom?
    @Published private(set) var isSupported: Bool = RoomCaptureSession.isSupported
    @Published private(set) var instruction: String = "Preparing…"
    @Published private(set) var liveWalls: Int = 0
    @Published private(set) var liveDoors: Int = 0
    @Published private(set) var liveWindows: Int = 0
    @Published private(set) var liveObjects: Int = 0
    @Published private(set) var isPaused: Bool = false

    let viewController = RoomCaptureHostController()

    init() {
        viewController.model = self
        refreshSupport()
    }

    func refreshSupport() {
        isSupported = RoomCaptureSession.isSupported
        if !isSupported {
            instruction = "This device has no LiDAR — RoomPlan needs a Pro iPhone/iPad with LiDAR."
        } else if phase == .idle {
            instruction = "Ready — walk slowly around the room"
        }
    }

    func start() {
        refreshSupport()
        guard isSupported else {
            phase = .failed(
                "RoomPlan needs a LiDAR iPhone or iPad (Pro models). The Simulator cannot scan real rooms."
            )
            return
        }
        finalRoom = nil
        liveWalls = 0
        liveDoors = 0
        liveWindows = 0
        liveObjects = 0
        isPaused = false
        phase = .scanning
        instruction = "Point at a wall, then walk the room edges slowly"
        viewController.startSession()
    }

    func stop() {
        guard phase == .scanning else { return }
        phase = .processing
        instruction = "Building LiDAR mesh and structure…"
        isPaused = false
        viewController.stopSession(process: true)
    }

    func cancel() {
        viewController.stopSession(process: false)
        phase = .idle
        finalRoom = nil
        isPaused = false
        instruction = "Cancelled"
        clearLiveStats()
    }

    func reset() {
        viewController.stopSession(process: false)
        finalRoom = nil
        phase = .idle
        isPaused = false
        clearLiveStats()
        instruction = isSupported ? "Ready — walk slowly around the room" : instruction
    }

    private func clearLiveStats() {
        liveWalls = 0
        liveDoors = 0
        liveWindows = 0
        liveObjects = 0
    }

    func setPhase(_ newPhase: Phase, instruction newInstruction: String? = nil) {
        onMain { [weak self] in
            guard let self else { return }
            self.phase = newPhase
            if let newInstruction {
                self.instruction = newInstruction
            }
        }
    }

    func setInstruction(_ text: String) {
        onMain { [weak self] in
            self?.instruction = text
        }
    }

    func updateLive(from room: CapturedRoom) {
        onMain { [weak self] in
            guard let self else { return }
            self.liveWalls = room.walls.count
            self.liveDoors = room.doors.count
            self.liveWindows = room.windows.count
            self.liveObjects = room.objects.count
        }
    }

    func setResult(room: CapturedRoom?, error: Error?) {
        onMain { [weak self] in
            guard let self else { return }
            if let error {
                self.phase = .failed(error.localizedDescription)
                self.instruction = "Could not finish processing"
                return
            }
            guard let room else {
                self.phase = .failed("No room data returned from LiDAR.")
                self.instruction = "Try scanning again — cover every wall"
                return
            }
            self.finalRoom = room
            self.liveWalls = room.walls.count
            self.liveDoors = room.doors.count
            self.liveWindows = room.windows.count
            self.liveObjects = room.objects.count
            self.phase = .completed
            self.instruction = "Scan complete — save to reopen later"
        }
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

// MARK: - Host UIViewController (RoomPlan + ARKit)

final class RoomCaptureHostController: UIViewController {
    weak var model: RoomCaptureModel?

    private var roomCaptureView: RoomCaptureView?
    private var isRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installCaptureViewIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        roomCaptureView?.frame = view.bounds
    }

    private func installCaptureViewIfNeeded() {
        guard roomCaptureView == nil else { return }

        let capture = RoomCaptureView(frame: view.bounds)
        capture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        capture.delegate = self
        view.addSubview(capture)
        roomCaptureView = capture
        capture.captureSession.delegate = self
    }

    func startSession() {
        loadViewIfNeeded()
        installCaptureViewIfNeeded()
        guard let roomCaptureView else {
            model?.setPhase(.failed("Could not create RoomCaptureView."), instruction: "Restart the app and try again")
            return
        }

        if isRunning {
            roomCaptureView.captureSession.stop()
            isRunning = false
        }

        let configuration = RoomCaptureSession.Configuration()
        isRunning = true
        roomCaptureView.captureSession.run(configuration: configuration)
    }

    func stopSession(process: Bool) {
        guard let roomCaptureView else { return }
        guard isRunning || process else { return }
        roomCaptureView.captureSession.stop()
        isRunning = false
    }

    func snapshotThumbnail() -> UIImage? {
        guard let roomCaptureView else { return nil }
        let bounds = roomCaptureView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        return UIGraphicsImageRenderer(bounds: bounds).image { _ in
            roomCaptureView.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
    }
}

// MARK: RoomCaptureViewDelegate

extension RoomCaptureHostController: RoomCaptureViewDelegate {
    func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData,
        error: Error?
    ) -> Bool {
        if let error {
            model?.setPhase(.failed(error.localizedDescription), instruction: "Capture error")
            return false
        }
        model?.setPhase(.processing, instruction: "Processing walls, doors, and objects…")
        return true
    }

    func captureView(
        didPresent processedResult: CapturedRoom,
        error: Error?
    ) {
        model?.setResult(room: processedResult, error: error)
    }
}

// MARK: RoomCaptureSessionDelegate

extension RoomCaptureHostController: RoomCaptureSessionDelegate {
    func captureSession(
        _ session: RoomCaptureSession,
        didUpdate room: CapturedRoom
    ) {
        model?.updateLive(from: room)
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didAdd room: CapturedRoom
    ) {
        model?.updateLive(from: room)
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didChange room: CapturedRoom
    ) {
        model?.updateLive(from: room)
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didRemove room: CapturedRoom
    ) {
        model?.updateLive(from: room)
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didProvide instruction: RoomCaptureSession.Instruction
    ) {
        model?.setInstruction(Self.humanReadable(instruction))
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didStartWith configuration: RoomCaptureSession.Configuration
    ) {
        model?.setPhase(.scanning, instruction: "LiDAR active — scan every wall and corner")
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: Error?
    ) {
        if let error {
            model?.setPhase(.failed(error.localizedDescription), instruction: "Session ended with error")
        }
    }

    /// Safe across SDK versions: known cases + plain `default` (always exhaustive).
    private static func humanReadable(_ instruction: RoomCaptureSession.Instruction) -> String {
        switch instruction {
        case .moveCloseToWall:
            return "Move closer to the wall"
        case .moveAwayFromWall:
            return "Step back from the wall"
        case .slowDown:
            return "Slow down — move more slowly"
        case .lowTexture:
            return "Low texture — point at corners, frames, or furniture edges"
        case .normal:
            return "Looking good — keep scanning the remaining walls"
        default:
            // Covers turnLeft / turnRight / any future coaching cases without compile errors
            return "Keep scanning — cover walls, doors, and windows"
        }
    }
}
