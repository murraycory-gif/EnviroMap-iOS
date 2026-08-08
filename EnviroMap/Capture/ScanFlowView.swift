import SwiftUI

/// Legacy entry name — always uses full-environment LiDAR + camera color scan.
/// (RoomPlan wall-only capture is no longer the primary path.)
struct ScanFlowView: View {
    var body: some View {
        FullEnvironmentScanView()
    }
}
