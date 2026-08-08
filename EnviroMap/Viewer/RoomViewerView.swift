import SwiftUI
import RealityKit
import ARKit
import UIKit

struct RoomViewerView: View {
    @EnvironmentObject private var store: SessionStore
    let session: RoomSession

    @State private var loadError: String?
    @State private var showShare = false

    var body: some View {
        ZStack {
            MeshPreviewRepresentable(
                usdzURL: store.usdzURL(for: session),
                onError: { loadError = $0 }
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                infoBar
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: store.shareItems(for: session))
        }
        .overlay {
            if let loadError {
                ContentUnavailableView(
                    "Could not open mesh",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .background(.ultraThinMaterial)
            }
        }
    }

    private var infoBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(session.wallCount) walls · \(session.objectCount) objects · \(session.doorCount) doors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Drag to orbit")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding()
    }
}

struct MeshPreviewRepresentable: UIViewRepresentable {
    let usdzURL: URL
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.cameraMode = .nonAR
        view.environment.background = .color(
            UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        )
        view.renderOptions.insert(.disableMotionBlur)
        context.coordinator.arView = view

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 55
        let camAnchor = AnchorEntity(world: .zero)
        camAnchor.addChild(camera)
        view.scene.addAnchor(camAnchor)
        context.coordinator.camera = camera
        context.coordinator.updateCamera()

        let light = DirectionalLight()
        light.light.color = .white
        light.light.intensity = 1400
        light.shadow = DirectionalLightComponent.Shadow()
        light.look(at: .zero, from: [4, 8, 3], relativeTo: nil)
        let lightAnchor = AnchorEntity(world: .zero)
        lightAnchor.addChild(light)
        view.scene.addAnchor(lightAnchor)

        let ambient = AnchorEntity(world: .zero)
        let ambientLight = PointLight()
        ambientLight.light.color = .white
        ambientLight.light.intensity = 400
        ambientLight.light.attenuationRadius = 20
        ambientLight.position = [0, 2, 0]
        ambient.addChild(ambientLight)
        view.scene.addAnchor(ambient)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let entity = try Entity.load(contentsOf: usdzURL)
                entity.generateCollisionShapes(recursive: true)

                let bounds = entity.visualBounds(relativeTo: nil)
                let extent = bounds.extents
                let maxDim = max(extent.x, max(extent.y, extent.z))
                if maxDim > 0.001 {
                    let scale = 3.0 / maxDim
                    entity.scale = SIMD3<Float>(repeating: scale)
                }
                entity.position = SIMD3<Float>(
                    -bounds.center.x * entity.scale.x,
                    -bounds.min.y * entity.scale.y,
                    -bounds.center.z * entity.scale.z
                )

                DispatchQueue.main.async {
                    let anchor = AnchorEntity(world: .zero)
                    anchor.addChild(entity)
                    view.scene.addAnchor(anchor)
                    context.coordinator.root = entity
                }
            } catch {
                DispatchQueue.main.async {
                    onError(error.localizedDescription)
                }
            }
        }

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    final class Coordinator: NSObject {
        weak var arView: ARView?
        var camera: PerspectiveCamera?
        var root: Entity?
        private var yaw: Float = 0.75
        private var pitch: Float = -0.4
        private var radius: Float = 5.2

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            yaw += Float(t.x) * 0.005
            pitch -= Float(t.y) * 0.004
            pitch = min(0.15, max(-1.25, pitch))
            g.setTranslation(.zero, in: g.view)
            updateCamera()
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            radius /= Float(g.scale)
            radius = min(14, max(1.8, radius))
            g.scale = 1
            updateCamera()
        }

        func updateCamera() {
            guard let camera else { return }
            let x = radius * cos(pitch) * sin(yaw)
            let y = radius * sin(-pitch) + 1.0
            let z = radius * cos(pitch) * cos(yaw)
            let pos = SIMD3<Float>(x, y, z)
            camera.position = pos
            camera.look(at: SIMD3<Float>(0, 0.6, 0), from: pos, relativeTo: nil)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
