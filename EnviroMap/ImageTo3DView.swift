import SwiftUI
import RealityKit
import PhotosUI
import UIKit

/// Places a photo as a textured 3D plane you can orbit (on-device, free).
/// Full photogrammetry needs Object Capture (Mac) — this is the mobile Image→3D path.
struct ImageTo3DView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                PhotoPlanePreview(image: image)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.blue)
                    Text("Image to 3D")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Pick a photo of a wall, product, or space. EnviroMap builds a 3D plane you can orbit — free, on-device.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo.on.rectangle")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(AppTheme.blue))
                    }
                }
            }

            if image != nil {
                VStack {
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text("Replace photo")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Image to 3D")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    await MainActor.run { image = ui }
                } else {
                    await MainActor.run { errorText = "Could not load image" }
                }
            }
        }
    }
}

struct PhotoPlanePreview: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.cameraMode = .nonAR
        view.environment.background = .color(.black)

        let cam = PerspectiveCamera()
        let camAnchor = AnchorEntity(world: .zero)
        camAnchor.addChild(cam)
        view.scene.addAnchor(camAnchor)
        context.coordinator.camera = cam
        context.coordinator.updateCamera()

        // Texture plane
        if let cg = image.cgImage {
            let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color))
            var mat = UnlitMaterial()
            if let tex {
                mat.color = .init(texture: .init(tex))
            } else {
                mat.color = .init(tint: .white)
            }
            let aspect = Float(image.size.width / max(image.size.height, 1))
            let height: Float = 1.6
            let width = height * aspect
            let plane = ModelEntity(
                mesh: .generatePlane(width: width, height: height),
                materials: [mat]
            )
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(plane)
            view.scene.addAnchor(anchor)
        }

        let light = DirectionalLight()
        light.light.intensity = 1000
        let la = AnchorEntity(world: [2, 3, 2])
        la.addChild(light)
        view.scene.addAnchor(la)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var camera: PerspectiveCamera?
        private var yaw: Float = 0.4
        private var pitch: Float = -0.15
        private var radius: Float = 2.4

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            yaw += Float(t.x) * 0.006
            pitch -= Float(t.y) * 0.005
            pitch = min(0.6, max(-0.8, pitch))
            g.setTranslation(.zero, in: g.view)
            updateCamera()
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            radius /= Float(g.scale)
            radius = min(6, max(1.2, radius))
            g.scale = 1
            updateCamera()
        }

        func updateCamera() {
            guard let camera else { return }
            let x = radius * cos(pitch) * sin(yaw)
            let y = radius * sin(-pitch)
            let z = radius * cos(pitch) * cos(yaw)
            let pos = SIMD3<Float>(x, y, z)
            camera.position = pos
            camera.look(at: .zero, from: pos, relativeTo: nil)
        }
    }
}
