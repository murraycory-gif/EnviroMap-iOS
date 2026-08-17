import SwiftUI
import RealityKit
import ARKit

/// AR polygon area — Home light chrome over the live camera.
struct AreaToolView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var areaSqM: Double?
    @State private var vertexCount = 0
    @State private var perimeterM: Double?
    @State private var resetToken = 0

    var body: some View {
        ZStack {
            AreaARView(
                areaSqM: $areaSqM,
                vertexCount: $vertexCount,
                perimeterM: $perimeterM,
                resetToken: resetToken
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                instructionChip
                    .padding(.top, 10)

                Spacer()

                panel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.card, in: Circle())
                    .shadow(color: AppTheme.blue.opacity(0.12), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Area")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity)

            Button {
                areaSqM = nil
                vertexCount = 0
                perimeterM = nil
                resetToken += 1
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.card, in: Circle())
                    .shadow(color: AppTheme.blue.opacity(0.12), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear Points")
        }
    }

    private var instructionChip: some View {
        Text(vertexCount < 3
             ? "Tap Corners Of The Floor (Min 3)"
             : "Keep Tapping Corners · Shape Closes Itself")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.card, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: 1))
            .shadow(color: AppTheme.blue.opacity(0.10), radius: 8, y: 2)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let a = areaSqM {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f", a * 10.7639))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.blue)
                            .monospacedDigit()
                        Text("Sq Ft")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.2f m²", a))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        if let p = perimeterM {
                            Text(String(format: "Perimeter %.1f Ft", p * 3.28084))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            } else {
                Text("Walk Around A Space And Tap Each Corner On The Floor")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.text)
            }

            Text("\(vertexCount) Points")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppTheme.blue.opacity(0.12), radius: 16, y: 6)
    }
}

struct AreaARView: UIViewRepresentable {
    @Binding var areaSqM: Double?
    @Binding var vertexCount: Int
    @Binding var perimeterM: Double?
    var resetToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        view.session.run(config)
        context.coordinator.arView = view
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.parent = self
        if resetToken != context.coordinator.lastReset {
            context.coordinator.lastReset = resetToken
            context.coordinator.clear()
        }
    }

    final class Coordinator: NSObject {
        var parent: AreaARView
        weak var arView: ARView?
        var lastReset = 0
        private var points: [SIMD3<Float>] = []
        private var markers: [AnchorEntity] = []

        init(parent: AreaARView) { self.parent = parent }

        func clear() {
            for a in markers { arView?.scene.removeAnchor(a) }
            markers.removeAll()
            points.removeAll()
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let arView else { return }
            let loc = g.location(in: arView)
            guard let hit = arView.raycast(from: loc, allowing: .existingPlaneGeometry, alignment: .horizontal).first
                    ?? arView.raycast(from: loc, allowing: .estimatedPlane, alignment: .horizontal).first
            else { return }

            let p = hit.worldTransform.columns.3
            let pt = SIMD3<Float>(p.x, p.y, p.z)
            points.append(pt)

            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 0.025),
                materials: [SimpleMaterial(color: UIColor(red: 0.15, green: 0.42, blue: 0.95, alpha: 1), isMetallic: false)]
            )
            let anchor = AnchorEntity(world: pt)
            anchor.addChild(sphere)
            arView.scene.addAnchor(anchor)
            markers.append(anchor)

            if points.count >= 2 {
                let a = points[points.count - 2]
                let b = points[points.count - 1]
                addEdge(from: a, to: b, in: arView)
            }

            parent.vertexCount = points.count
            if points.count >= 3 {
                parent.areaSqM = polygonArea(points)
                parent.perimeterM = perimeter(points)
            }
        }

        private func addEdge(from a: SIMD3<Float>, to b: SIMD3<Float>, in arView: ARView) {
            let mid = (a + b) / 2
            let dist = simd_distance(a, b)
            let box = ModelEntity(
                mesh: .generateBox(size: [0.01, 0.01, dist]),
                materials: [SimpleMaterial(color: UIColor(red: 0.15, green: 0.42, blue: 0.95, alpha: 1), isMetallic: false)]
            )
            let anchor = AnchorEntity(world: mid)
            let dir = simd_normalize(b - a)
            anchor.look(at: mid + dir, from: mid, relativeTo: nil)
            anchor.addChild(box)
            arView.scene.addAnchor(anchor)
            markers.append(anchor)
        }

        private func polygonArea(_ pts: [SIMD3<Float>]) -> Double {
            guard pts.count >= 3 else { return 0 }
            var sum: Float = 0
            for i in 0..<pts.count {
                let j = (i + 1) % pts.count
                sum += pts[i].x * pts[j].z
                sum -= pts[j].x * pts[i].z
            }
            return Double(abs(sum) * 0.5)
        }

        private func perimeter(_ pts: [SIMD3<Float>]) -> Double {
            guard pts.count >= 2 else { return 0 }
            var p: Float = 0
            for i in 0..<pts.count {
                let j = (i + 1) % pts.count
                p += simd_distance(pts[i], pts[j])
            }
            return Double(p)
        }
    }
}
