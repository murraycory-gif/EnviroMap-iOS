import SwiftUI
import RoomPlan

/// Embeds Apple’s RoomCapture host controller (LiDAR + AR) in SwiftUI.
struct RoomCaptureRepresentable: UIViewControllerRepresentable {
    @ObservedObject var model: RoomCaptureModel

    func makeUIViewController(context: Context) -> RoomCaptureHostController {
        // Same instance owned by the model so start/stop share the live RoomCaptureView
        model.viewController
    }

    func updateUIViewController(_ uiViewController: RoomCaptureHostController, context: Context) {
        // Lifecycle is driven by RoomCaptureModel.start() / stop() / cancel()
    }
}
