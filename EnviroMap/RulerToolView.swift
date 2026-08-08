import SwiftUI
import RealityKit
import ARKit

/// AR distance ruler — tap two points on surfaces.
struct RulerToolView: View {
    @State private var distanceMeters: Double?
    @State private var pointCount = 0
    @State private var history: [Double] = []

    var body: some View {
        ZStack {
            RulerARView(
                distanceMeters: $distanceMeters,
                pointCount: $pointCount,
                onMeasurement: { m in
                    history.insert(m, at: 0)
                    if history.count > 12 { history = Array(history.prefix(12)) }
                }
            )
            .ignoresSafeArea()

            VStack {
                instructionBanner
                Spacer()
                bottomPanel
            }
        }
        .navigationTitle("Ruler")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var instructionBanner: some View {
        Text(pointCount == 0 ? "Tap a surface for point A" : pointCount == 1 ? "Tap point B to measure" : "Tap to start a new measure")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
    }

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if let d = distanceMeters {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", d * 3.28084))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("ft")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(String(format: "%.2f m", d))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            } else {
                Text("Aim at floors, walls, or furniture")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !history.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, m in
                            Text(String(format: "%.2f ft", m * 3.28084))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(AppTheme.blue.opacity(0.9)))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .padding()
    }
}

struct RulerARView: UIViewRepresentable {
    @Binding var distanceMeters: Double?
    @Binding var pointCount: Int
    var onMeasurement: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.run(config)
        view.session.delegate = context.coordinator
        context.coordinator.arView = view

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        // Crosshair
        let cross = UIView(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        cross.backgroundColor = .clear
        cross.isUserInteractionEnabled = false
        cross.tag = 99
        let h = UIView(frame: CGRect(x: 0, y: 10, width: 22, height: 2))
        h.backgroundColor = UIColor(red: 0.2, green: 0.5, blue: 1, alpha: 0.95)
        let v = UIView(frame: CGRect(x: 10, y: 0, width: 2, height: 22))
        v.backgroundColor = UIColor(red: 0.2, green: 0.5, blue: 1, alpha: 0.95)
        cross.addSubview(h)
        cross.addSubview(v)
        view.addSubview(cross)
        context.coordinator.crosshair = cross

        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async {
            if let cross = context.coordinator.crosshair {
                cross.center = CGPoint(x: uiView.bounds.midX, y: uiView.bounds.midY)
            }
        }
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        var parent: RulerARView
        weak var arView: ARView?
        var crosshair: UIView?
        private var points: [SIMD3<Float>] = []
        private var markers: [AnchorEntity] = []
        private var lineAnchor: AnchorEntity?

        init(parent: RulerARView) {
            self.parent = parent
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let arView else { return }
            let loc = g.location(in: arView)
            // Prefer mesh / existing plane raycast
            if let result = arView.raycast(from: loc, allowing: .estimatedPlane, alignment: .any).first {
                addPoint(result.worldTransform.columns.3.xyz, in: arView)
            } else if let result = arView.raycast(from: loc, allowing: .existingPlaneGeometry, alignment: .any).first {
                addPoint(result.worldTransform.columns.3.xyz, in: arView)
            }
        }

        private func addPoint(_ p: SIMD3<Float>, in arView: ARView) {
            if points.count >= 2 {
                // reset
                markers.forEach { $0.removeFromParent() }
                markers.removeAll()
                lineAnchor?.removeFromParent()
                lineAnchor = nil
                points.removeAll()
            }

            points.append(p)
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 0.02),
                materials: [SimpleMaterial(color: UIColor.systemBlue, isMetallic: false)]
            )
            let anchor = AnchorEntity(world: p)
            anchor.addChild(sphere)
            arView.scene.addAnchor(anchor)
            markers.append(anchor)

            parent.pointCount = points.count

            if points.count == 2 {
                let d = Double(simd_distance(points[0], points[1]))
                parent.distanceMeters = d
                parent.onMeasurement(d)
                drawLine(from: points[0], to: points[1], in: arView)
            }
        }

        private func drawLine(from a: SIMD3<Float>, to b: SIMD3<Float>, in arView: ARView) {
            let mid = (a + b) / 2
            let dist = simd_distance(a, b)
            let box = ModelEntity(
                mesh: .generateBox(size: [0.008, 0.008, dist], cornerRadius: 0.002),
                materials: [SimpleMaterial(color: UIColor.systemBlue, isMetallic: false)]
            )
            let anchor = AnchorEntity(world: mid)
            // orient Z toward b-a
            let dir = simd_normalize(b - a)
            anchor.look(at: mid + dir, from: mid, relativeTo: nil)
            anchor.addChild(box)
            arView.scene.addAnchor(anchor)
            lineAnchor = anchor
        }
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
