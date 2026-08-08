import Foundation
import RoomPlan
import UIKit
import Combine

// MARK: - SwiftUI model (plain class — no NSObject)

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

    /// Host UIViewController that owns RoomCaptureView (Apple's recommended pattern).
    let viewController = RoomCaptureHostController()

    init() {
        viewController.model = self
        if !isSupported {
            instruction = "This device does not support RoomPlan (LiDAR required)."
        } else {
            instruction = "Ready"
        }
    }

    func start() {
        guard isSupported else {
            phase = .failed(
                "RoomPlan needs a LiDAR iPhone or iPad (12 Pro or later Pro models). The Simulator cannot scan."
            )
            return
        }
        finalRoom = nil
        phase = .scanning
        instruction = "Move slowly. Point at walls, corners, doors, and windows."
        viewController.startSession()
    }

    func stop() {
        guard phase == .scanning else { return }
        phase = .processing
        instruction = "Building mesh from LiDAR…"
        viewController.stopSession()
    }

    func cancel() {
        viewController.stopSession()
        phase = .idle
        finalRoom = nil
        instruction = "Cancelled"
    }

    func reset() {
        viewController.stopSession()
        finalRoom = nil
        phase = .idle
        instruction = "Ready"
    }

    func setPhase(_ newPhase: Phase, instruction newInstruction: String? = nil) {
        let apply = { [weak self] in
            guard let self else { return }
            self.phase = newPhase
            if let newInstruction {
                self.instruction = newInstruction
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func setResult(room: CapturedRoom?, error: Error?) {
        let apply = { [weak self] in
            guard let self else { return }
            if let error {
                self.phase = .failed(error.localizedDescription)
                self.instruction = "Processing failed"
                return
            }
            guard let room else {
                self.phase = .failed("No room data returned.")
                return
            }
            self.finalRoom = room
            self.phase = .completed
            self.instruction = "Scan complete — save to reopen later"
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

// MARK: - Host controller (UIViewController already conforms to NSCoding)

/// Matches Apple's RoomPlan sample: UIViewController + RoomCaptureViewDelegate.
final class RoomCaptureHostController: UIViewController, RoomCaptureViewDelegate {
    weak var model: RoomCaptureModel?
    private var roomCaptureView: RoomCaptureView?
    private var isRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let capture = RoomCaptureView(frame: view.bounds)
        capture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        capture.delegate = self
        view.addSubview(capture)
        roomCaptureView = capture
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        roomCaptureView?.frame = view.bounds
    }

    func startSession() {
        if roomCaptureView == nil {
            loadViewIfNeeded()
        }
        guard let roomCaptureView else { return }
        isRunning = true
        let configuration = RoomCaptureSession.Configuration()
        roomCaptureView.captureSession.run(configuration: configuration)
    }

    func stopSession() {
        guard isRunning else { return }
        roomCaptureView?.captureSession.stop()
        isRunning = false
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData,
        error: Error?
    ) -> Bool {
        if let error {
            model?.setPhase(.failed(error.localizedDescription))
            return false
        }
        model?.setPhase(.processing, instruction: "Processing room structure…")
        return true
    }

    func captureView(
        didPresent processedResult: CapturedRoom,
        error: Error?
    ) {
        model?.setResult(room: processedResult, error: error)
    }
}
