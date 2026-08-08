import SwiftUI
import RealityKit

/// Generate a simple room box mesh from a text description (dimensions).
/// Free, on-device — not cloud AI. Parses sizes like "12x10 room" or "living room 4m by 5m".
struct TextTo3DView: View {
    @State private var prompt = "Living room 12 ft by 15 ft, 9 ft ceiling"
    @State private var dims: RoomDims = RoomDims(widthFt: 12, depthFt: 15, heightFt: 9)
    @State private var parsedNote = ""

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                TextTo3DPreview(dims: dims)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Describe a room")
                        .font(.headline)
                        .foregroundStyle(.white)

                    TextField("e.g. kitchen 10x12 with 8 ft ceiling", text: $prompt, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .foregroundStyle(.white)

                    if !parsedNote.isEmpty {
                        Text(parsedNote)
                            .font(.caption)
                            .foregroundStyle(AppTheme.blue)
                    }

                    Button {
                        let r = RoomDims.parse(prompt)
                        dims = r.dims
                        parsedNote = r.note
                    } label: {
                        Label("Generate 3D room", systemImage: "wand.and.stars")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(AppTheme.blue))
                    }
                    .buttonStyle(.plain)

                    Text("Free on-device box model from dimensions. Full AI mesh generation can plug in later — no charges now.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(18)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24
                    )
                    .fill(Color.white.opacity(0.06))
                )
            }
        }
        .navigationTitle("Text to 3D")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let r = RoomDims.parse(prompt)
            dims = r.dims
            parsedNote = r.note
        }
    }
}

struct RoomDims: Equatable {
    var widthFt: Double
    var depthFt: Double
    var heightFt: Double

    var widthM: Float { Float(widthFt * 0.3048) }
    var depthM: Float { Float(depthFt * 0.3048) }
    var heightM: Float { Float(heightFt * 0.3048) }

    static func parse(_ text: String) -> (dims: RoomDims, note: String) {
        let lower = text.lowercased()
        // Find numbers
        let pattern = #"(\d+(?:\.\d+)?)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(lower.startIndex..., in: lower)
        let matches = regex?.matches(in: lower, range: range) ?? []
        let nums = matches.compactMap { m -> Double? in
            guard let r = Range(m.range, in: lower) else { return nil }
            return Double(lower[r])
        }

        let isMeters = lower.contains("meter") || lower.contains(" metre") || lower.contains(" m ") || lower.hasSuffix(" m") || lower.contains("m by") || lower.contains("m x")

        var w = 12.0, d = 12.0, h = 9.0
        if nums.count >= 2 {
            w = nums[0]
            d = nums[1]
        }
        if nums.count >= 3 {
            h = nums[2]
        } else if lower.contains("ceiling") || lower.contains("height") {
            // keep default height
        }

        if isMeters {
            w *= 3.28084
            d *= 3.28084
            if nums.count >= 3 { h *= 3.28084 }
        }

        w = min(max(w, 4), 80)
        d = min(max(d, 4), 80)
        h = min(max(h, 7), 20)

        let note = String(format: "Parsed ≈ %.0f × %.0f ft, ceiling %.0f ft", w, d, h)
        return (RoomDims(widthFt: w, depthFt: d, heightFt: h), note)
    }
}

struct TextTo3DPreview: UIViewRepresentable {
    var dims: RoomDims

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.cameraMode = .nonAR
        view.environment.background = .color(UIColor(red: 0.05, green: 0.06, blue: 0.1, alpha: 1))
        context.coordinator.arView = view

        let cam = PerspectiveCamera()
        let ca = AnchorEntity(world: .zero)
        ca.addChild(cam)
        view.scene.addAnchor(ca)
        context.coordinator.camera = cam

        let light = DirectionalLight()
        light.light.intensity = 1200
        light.shadow = DirectionalLightComponent.Shadow()
        let la = AnchorEntity(world: [3, 6, 2])
        la.addChild(light)
        view.scene.addAnchor(la)

        context.coordinator.rebuild(dims: dims)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pinch)

        context.coordinator.updateCamera()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.rebuild(dims: dims)
    }

    final class Coordinator: NSObject {
        weak var arView: ARView?
        var camera: PerspectiveCamera?
        private var roomAnchor: AnchorEntity?
        private var yaw: Float = 0.9
        private var pitch: Float = -0.45
        private var radius: Float = 8
        private var lastDims: RoomDims?

        func rebuild(dims: RoomDims) {
            guard lastDims != dims, let arView else {
                if roomAnchor == nil, let arView {
                    forceBuild(dims: dims, in: arView)
                }
                return
            }
            forceBuild(dims: dims, in: arView)
            lastDims = dims
        }

        private func forceBuild(dims: RoomDims, in arView: ARView) {
            roomAnchor?.removeFromParent()
            let root = AnchorEntity(world: .zero)

            let w = dims.widthM
            let d = dims.depthM
            let h = dims.heightM
            let t: Float = 0.08

            let wallMat = SimpleMaterial(color: UIColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 0.55), isMetallic: false)
            let floorMat = SimpleMaterial(color: UIColor(white: 0.85, alpha: 1), isMetallic: false)

            // Floor
            let floor = ModelEntity(mesh: .generatePlane(width: w, depth: d), materials: [floorMat])
            floor.position = [0, 0, 0]
            root.addChild(floor)

            // Walls (thin boxes)
            func wall(size: SIMD3<Float>, pos: SIMD3<Float>) {
                let e = ModelEntity(mesh: .generateBox(size: size), materials: [wallMat])
                e.position = pos
                root.addChild(e)
            }
            wall(size: [w, h, t], pos: [0, h / 2, -d / 2])
            wall(size: [w, h, t], pos: [0, h / 2, d / 2])
            wall(size: [t, h, d], pos: [-w / 2, h / 2, 0])
            wall(size: [t, h, d], pos: [w / 2, h / 2, 0])

            arView.scene.addAnchor(root)
            roomAnchor = root

            // Fit camera radius to room
            radius = max(w, d, h) * 1.8
            updateCamera()
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            yaw += Float(t.x) * 0.006
            pitch -= Float(t.y) * 0.005
            pitch = min(-0.1, max(-1.2, pitch))
            g.setTranslation(.zero, in: g.view)
            updateCamera()
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            radius /= Float(g.scale)
            radius = min(30, max(3, radius))
            g.scale = 1
            updateCamera()
        }

        func updateCamera() {
            guard let camera else { return }
            let x = radius * cos(pitch) * sin(yaw)
            let y = radius * sin(-pitch) + 1.2
            let z = radius * cos(pitch) * cos(yaw)
            let pos = SIMD3<Float>(x, y, z)
            camera.position = pos
            camera.look(at: SIMD3<Float>(0, 1, 0), from: pos, relativeTo: nil)
        }
    }
}
