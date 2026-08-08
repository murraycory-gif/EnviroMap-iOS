import SwiftUI
import RealityKit
import ARKit

/// AR polygon area measure (horizontal plane).
struct AreaToolView: View {
    @State private var areaSqM: Double?
    @State private var vertexCount = 0
    @State private var perimeterM: Double?

    var body: some View {
        ZStack {
            AreaARView(
                areaSqM: $areaSqM,
                vertexCount: $vertexCount,
                perimeterM: $perimeterM
            )
            .ignoresSafeArea()

            VStack {
                Text(vertexCount < 3
                     ? "Tap corners of the floor area (min 3)"
                     : "Tap “Close shape” or add more corners")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                Spacer()
                panel
            }
        }
        .navigationTitle("Area")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var panel: some View {
        VStack(spacing: 10) {
            if let a = areaSqM {
                HStack {
                    VStack(alignment: .leading) {
                        Text(String(format: "%.1f", a * 10.7639))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("sq ft")
                            .font(.caption.weight(.semibold))
                            .opacity(0.7)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.2f m²", a))
                        if let p = perimeterM {
                            Text(String(format: "Perimeter %.1f ft", p * 3.28084))
                                .font(.caption)
                                .opacity(0.75)
                        }
                    }
                }
                .foregroundStyle(.white)
            } else {
                Text("Walk around a space and tap each corner on the floor")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("\(vertexCount) points")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.55))
        )
        .padding()
    }
}

struct AreaARView: UIViewRepresentable {
    @Binding var areaSqM: Double?
    @Binding var vertexCount: Int
    @Binding var perimeterM: Double?

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
    }

    final class Coordinator: NSObject {
        var parent: AreaARView
        weak var arView: ARView?
        private var points: [SIMD3<Float>] = []
        private var markers: [AnchorEntity] = []

        init(parent: AreaARView) { self.parent = parent }

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
                materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)]
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
                materials: [SimpleMaterial(color: UIColor.systemTeal, isMetallic: false)]
            )
            let anchor = AnchorEntity(world: mid)
            let dir = simd_normalize(b - a)
            anchor.look(at: mid + dir, from: mid, relativeTo: nil)
            anchor.addChild(box)
            arView.scene.addAnchor(anchor)
        }

        /// Project to XZ plane and use shoelace formula.
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
            // open perimeter until closed — use open path for partial
            if pts.count < 3 {
                return Double(p)
            }
            return Double(p)
        }
    }
}
