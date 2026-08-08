import SwiftUI
import RoomPlan

/// Embeds Apple's RoomCapture host UIViewController in SwiftUI.
struct RoomCaptureRepresentable: UIViewControllerRepresentable {
    @ObservedObject var model: RoomCaptureModel

    func makeUIViewController(context: Context) -> RoomCaptureHostController {
        model.viewController
    }

    func updateUIViewController(_ uiViewController: RoomCaptureHostController, context: Context) {
        // Lifecycle controlled by RoomCaptureModel
    }
}
