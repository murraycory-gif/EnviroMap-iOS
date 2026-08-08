import Foundation
import RoomPlan
import UIKit
import Combine
import ARKit

// MARK: - SwiftUI-facing model

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
    @Published private(set) var tipText: String = ""

    let viewController = RoomCaptureHostController()

    /// User intentionally stopped / cancelled — ignore trailing session errors.
    private var ignoreSessionErrors = false

    init() {
        viewController.model = self
        refreshSupport()
    }

    func refreshSupport() {
        isSupported = RoomCaptureSession.isSupported
        if !isSupported {
            instruction = "This device has no LiDAR — RoomPlan needs a Pro iPhone/iPad with LiDAR."
        } else if phase == .idle {
            instruction = "Bright light · move slowly · face walls"
            tipText = "Tip: Point at a clear wall first, then walk the edges."
        }
    }

    func start() {
        refreshSupport()
        guard isSupported else {
            phase = .failed(
                "RoomPlan needs a LiDAR Pro iPhone. Simulator cannot scan."
            )
            return
        }
        ignoreSessionErrors = false
        finalRoom = nil
        clearLiveStats()
        phase = .scanning
        instruction = "Find a wall — hold still 2 seconds, then walk slowly"
        tipText = "Good light helps. Avoid pure white empty walls only."
        viewController.startSession(resetHard: true)
    }

    func stop() {
        guard phase == .scanning else { return }
        ignoreSessionErrors = true
        phase = .processing
        instruction = "Building LiDAR mesh…"
        tipText = ""
        viewController.stopSession()
    }

    func cancel() {
        ignoreSessionErrors = true
        viewController.stopSession()
        phase = .idle
        finalRoom = nil
        instruction = "Cancelled"
        tipText = ""
        clearLiveStats()
    }

    func reset() {
        ignoreSessionErrors = true
        viewController.stopSession()
        viewController.tearDownCaptureView()
        finalRoom = nil
        phase = .idle
        clearLiveStats()
        instruction = isSupported ? "Ready — good light, move slowly" : instruction
        tipText = "Tip: Start facing a wall with shelves, doors, or corners."
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
                // If user already stopped for processing, still try to surface real process errors
                self.phase = .failed(Self.friendlyError(error))
                self.instruction = "Could not finish"
                self.tipText = Self.recoveryTip(for: error)
                return
            }
            guard let room else {
                self.phase = .failed("No room data returned.")
                self.instruction = "Scan longer — cover every wall"
                self.tipText = "Walk a full loop of the room before tapping Done."
                return
            }
            self.finalRoom = room
            self.liveWalls = room.walls.count
            self.liveDoors = room.doors.count
            self.liveWindows = room.windows.count
            self.liveObjects = room.objects.count
            self.phase = .completed
            self.instruction = "Scan complete — save to reopen later"
            self.tipText = ""
        }
    }

    func handleSessionEnd(error: Error?) {
        onMain { [weak self] in
            guard let self else { return }
            // User stopped / cancelled — don't flash world-tracking noise
            if self.ignoreSessionErrors {
                return
            }
            // Already completed or processing successfully
            if self.phase == .completed || self.phase == .processing {
                return
            }
            guard let error else { return }
            self.phase = .failed(Self.friendlyError(error))
            self.instruction = "Session ended with error"
            self.tipText = Self.recoveryTip(for: error)
        }
    }

    /// Map ARKit/RoomPlan errors to plain language.
    static func friendlyError(_ error: Error) -> String {
        let ns = error as NSError
        let text = error.localizedDescription.lowercased()
        if text.contains("world tracking") || ns.code == 102 /* worldTrackingFailed often */ {
            return "World tracking lost"
        }
        if text.contains("sensor") || text.contains("camera") {
            return "Camera / sensor issue"
        }
        return error.localizedDescription
    }

    static func recoveryTip(for error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("world tracking") {
            return """
            Try this:
            • Turn on more lights
            • Hold phone steady 2–3 sec on a wall
            • Move slowly (no quick spins)
            • Point at corners, doors, shelves — not blank walls only
            • Close other AR apps, then Try again
            """
        }
        return "Tap Try again. Use bright light and move slowly along the walls."
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

// MARK: - Host UIViewController

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

    /// Hard reset recreates RoomCaptureView so ARKit gets a clean world map.
    func startSession(resetHard: Bool = false) {
        loadViewIfNeeded()

        if resetHard {
            tearDownCaptureView()
        }

        installCaptureViewIfNeeded()
        guard let roomCaptureView else {
            model?.setPhase(.failed("Could not start camera."), instruction: "Restart the app")
            return
        }

        if isRunning {
            roomCaptureView.captureSession.stop()
            isRunning = false
        }

        // Brief delay after teardown so ARSession can release the camera
        let runBlock = { [weak self] in
            guard let self, let roomCaptureView = self.roomCaptureView else { return }
            let configuration = RoomCaptureSession.Configuration()
            self.isRunning = true
            roomCaptureView.captureSession.run(configuration: configuration)
        }

        if resetHard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: runBlock)
        } else {
            runBlock()
        }
    }

    func stopSession() {
        guard let roomCaptureView else { return }
        if isRunning {
            roomCaptureView.captureSession.stop()
            isRunning = false
        }
    }

    func tearDownCaptureView() {
        if isRunning {
            roomCaptureView?.captureSession.stop()
            isRunning = false
        }
        roomCaptureView?.removeFromSuperview()
        roomCaptureView = nil
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
            model?.setResult(room: nil, error: error)
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
        model?.setPhase(.scanning, instruction: "Hold still on a wall, then walk slowly")
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: Error?
    ) {
        model?.handleSessionEnd(error: error)
    }

    private static func humanReadable(_ instruction: RoomCaptureSession.Instruction) -> String {
        switch instruction {
        case .moveCloseToWall:
            return "Move closer to the wall"
        case .moveAwayFromWall:
            return "Step back from the wall"
        case .slowDown:
            return "Slow down"
        case .lowTexture:
            return "Need more detail — aim at corners, doors, shelves"
        case .normal:
            return "Tracking OK — keep scanning walls"
        default:
            return "Move slowly along the walls"
        }
    }
}
