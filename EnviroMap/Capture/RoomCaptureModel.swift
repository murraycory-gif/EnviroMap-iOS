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
    @Published private(set) var trackingLabel: String = ""

    let viewController = RoomCaptureHostController()

    /// User intentionally stopped / cancelled — ignore trailing session errors.
    fileprivate var ignoreSessionErrors = false
    private var didRequestStart = false

    init() {
        viewController.model = self
        refreshSupport()
    }

    func refreshSupport() {
        isSupported = RoomCaptureSession.isSupported
        if !isSupported {
            instruction = "This device has no LiDAR — RoomPlan needs a Pro iPhone/iPad with LiDAR."
        } else if phase == .idle {
            instruction = "Ready"
            tipText = "Keep the back cameras uncovered. Hold upright, start on a wall with detail."
        }
    }

    func start() {
        refreshSupport()
        guard isSupported else {
            phase = .failed("RoomPlan needs a LiDAR Pro iPhone.")
            return
        }
        // Prevent double-start (onAppear + button)
        guard !didRequestStart || phase == .failed || phase == .idle || phase == .completed else {
            return
        }
        didRequestStart = true
        ignoreSessionErrors = false
        finalRoom = nil
        clearLiveStats()
        phase = .scanning
        instruction = "Hold phone upright on a wall for 3 seconds…"
        tipText = "Don’t cover the back camera/LiDAR bar. Move only after tracking looks stable."
        trackingLabel = "Starting…"
        viewController.startSession(resetHard: true)
    }

    func stop() {
        guard phase == .scanning else { return }
        ignoreSessionErrors = true
        phase = .processing
        instruction = "Building LiDAR mesh…"
        tipText = ""
        trackingLabel = ""
        viewController.stopSession()
    }

    func cancel() {
        ignoreSessionErrors = true
        didRequestStart = false
        viewController.stopSession()
        phase = .idle
        finalRoom = nil
        instruction = "Cancelled"
        tipText = ""
        trackingLabel = ""
        clearLiveStats()
    }

    func reset() {
        ignoreSessionErrors = true
        didRequestStart = false
        viewController.stopSession()
        viewController.tearDownCaptureView()
        finalRoom = nil
        phase = .idle
        clearLiveStats()
        trackingLabel = ""
        instruction = isSupported ? "Ready" : instruction
        tipText = "Tip: Don’t block LiDAR on the back. Start facing a corner or door frame."
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

    func setTrackingLabel(_ text: String) {
        onMain { [weak self] in
            self?.trackingLabel = text
        }
    }

    func updateLive(from room: CapturedRoom) {
        onMain { [weak self] in
            guard let self else { return }
            self.liveWalls = room.walls.count
            self.liveDoors = room.doors.count
            self.liveWindows = room.windows.count
            self.liveObjects = room.objects.count
            if room.walls.count > 0 {
                self.trackingLabel = "Tracking OK"
            }
        }
    }

    func setResult(room: CapturedRoom?, error: Error?) {
        onMain { [weak self] in
            guard let self else { return }
            self.didRequestStart = false
            if let error {
                self.phase = .failed(Self.friendlyError(error))
                self.instruction = "Could not finish"
                self.tipText = Self.recoveryTip(for: error)
                self.trackingLabel = ""
                return
            }
            guard let room else {
                self.phase = .failed("No room data returned.")
                self.instruction = "Scan longer — cover every wall"
                self.tipText = "Walk a full loop before Done."
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
            self.trackingLabel = ""
        }
    }

    func handleSessionEnd(error: Error?) {
        onMain { [weak self] in
            guard let self else { return }
            if self.ignoreSessionErrors { return }
            if self.phase == .completed || self.phase == .processing { return }
            guard let error else { return }
            self.didRequestStart = false
            self.phase = .failed(Self.friendlyError(error))
            self.instruction = "Session ended with error"
            self.tipText = Self.recoveryTip(for: error)
            self.trackingLabel = ""
        }
    }

    static func friendlyError(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        let ns = error as NSError
        if text.contains("world tracking") {
            return "World tracking lost"
        }
        if text.contains("camera") {
            return "Camera unavailable — close other apps using the camera"
        }
        return error.localizedDescription.isEmpty ? "Error \(ns.code)" : error.localizedDescription
    }

    static func recoveryTip(for error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("world tracking") {
            return """
            Light is fine — try these instead:
            • Remove thick case / don’t cover the back camera bar (LiDAR)
            • Hold phone upright, start on a corner or door frame
            • Stay still 3 seconds, then walk slowly
            • Restart the iPhone if it keeps failing
            • Try a different room once to confirm
            """
        }
        return "Tap Try again. Close other camera apps first."
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() }
        else { DispatchQueue.main.async(execute: block) }
    }
}

// MARK: - Host

final class RoomCaptureHostController: UIViewController {
    weak var model: RoomCaptureModel?

    private var roomCaptureView: RoomCaptureView?
    private var isRunning = false
    private var startWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        roomCaptureView?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Ensure layout is non-zero before any run
        roomCaptureView?.frame = view.bounds
    }

    private func installCaptureViewIfNeeded() {
        guard roomCaptureView == nil else { return }
        guard view.bounds.width > 10, view.bounds.height > 10 else { return }

        let capture = RoomCaptureView(frame: view.bounds)
        capture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        capture.delegate = self
        view.addSubview(capture)
        roomCaptureView = capture
        capture.captureSession.delegate = self
    }

    func startSession(resetHard: Bool = false) {
        loadViewIfNeeded()
        startWorkItem?.cancel()

        if resetHard {
            tearDownCaptureView()
        }

        // Wait until view has real size + camera stack released
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.view.layoutIfNeeded()
            self.installCaptureViewIfNeeded()

            // Retry install once if bounds were zero
            if self.roomCaptureView == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self else { return }
                    self.view.layoutIfNeeded()
                    self.installCaptureViewIfNeeded()
                    self.runCapture()
                }
                return
            }
            self.runCapture()
        }
        startWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (resetHard ? 0.45 : 0.15), execute: work)
    }

    private func runCapture() {
        guard let roomCaptureView else {
            model?.setPhase(.failed("Could not start camera."), instruction: "Close and reopen Scan")
            return
        }
        roomCaptureView.frame = view.bounds

        if isRunning {
            roomCaptureView.captureSession.stop()
            isRunning = false
        }

        let configuration = RoomCaptureSession.Configuration()
        isRunning = true
        roomCaptureView.captureSession.run(configuration: configuration)
        model?.setTrackingLabel("Locking position…")
    }

    func stopSession() {
        startWorkItem?.cancel()
        startWorkItem = nil
        guard let roomCaptureView else { return }
        if isRunning {
            roomCaptureView.captureSession.stop()
            isRunning = false
        }
    }

    func tearDownCaptureView() {
        startWorkItem?.cancel()
        startWorkItem = nil
        if isRunning {
            roomCaptureView?.captureSession.stop()
            isRunning = false
        }
        roomCaptureView?.delegate = nil
        roomCaptureView?.captureSession.delegate = nil
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
        // Coaching "normal" means tracking is healthy
        if instruction == .normal {
            model?.setTrackingLabel("Tracking OK")
        } else if instruction == .lowTexture {
            model?.setTrackingLabel("Need more detail")
        } else if instruction == .slowDown {
            model?.setTrackingLabel("Slow down")
        }
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didStartWith configuration: RoomCaptureSession.Configuration
    ) {
        model?.setPhase(.scanning, instruction: "Hold still 3 sec, then walk walls slowly")
        model?.setTrackingLabel("Session started")
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
            return "Aim at corners / door frames / shelves"
        case .normal:
            return "Tracking OK — keep scanning"
        default:
            return "Move slowly along the walls"
        }
    }
}
