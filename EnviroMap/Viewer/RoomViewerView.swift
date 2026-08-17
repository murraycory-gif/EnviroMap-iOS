import SwiftUI
import SceneKit
import UIKit
import QuickLook
import simd

/// Offline 3D mesh viewer (SceneKit — no ARView, won’t freeze the UI).
struct RoomViewerView: View {
    @EnvironmentObject private var store: SessionStore
    let session: RoomSession

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showShare = false
    @State private var showQuickLook = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    /// Prefer dense full-space mesh; fall back to RoomPlan structure.
    private var meshURL: URL {
        store.preferredMeshURL(for: session)
    }

    private var structureURL: URL {
        store.usdzURL(for: session)
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: meshURL.path)
    }

    private var isDenseMesh: Bool {
        session.hasDenseMesh || store.denseMeshURL(for: session) != nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text("Could Not Open Scan")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            } else if !fileExists {
                VStack(spacing: 16) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.blue)
                    Text("Scan File Missing")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Scan Again And Save.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
            } else {
                MeshSceneView(
                    usdzURL: meshURL,
                    isLoading: $isLoading,
                    loadError: $loadError
                )
                .ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white).scaleEffect(1.2)
                        Text("Loading Scan…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }

            // Simple top chrome: Delete · Title · Done
            VStack {
                HStack(spacing: 12) {
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.red.opacity(0.9), in: Circle())
                    }
                    .accessibilityLabel("Delete Scan")

                    Spacer(minLength: 0)

                    Text(session.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer(minLength: 0)

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.blue, in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Simple how-to + status
                if !isLoading, loadError == nil, fileExists {
                    VStack(spacing: 8) {
                        Text(BuildStamp.id)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.7))
                        Text("Drag To Spin  ·  Pinch To Zoom")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(isDenseMesh ? "Full Color Scan" : "Structure Scan")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .alert("Delete This Scan?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                store.delete(session)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This Cannot Be Undone.")
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: store.shareItems(for: session))
        }
        .sheet(isPresented: $showQuickLook) {
            QuickLookUSDZ(url: meshURL)
                .ignoresSafeArea()
        }
    }
}

// MARK: - SceneKit preview (lightweight, no AR session)

struct MeshSceneView: UIViewRepresentable {
    let usdzURL: URL
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = UIColor.black
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        view.rendersContinuously = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        // Empty scene first so navigation isn’t blocked
        view.scene = SCNScene()
        context.coordinator.view = view

        // Load mesh off the main path after first frame
        context.coordinator.load(url: usdzURL, isLoading: $isLoading, loadError: $loadError)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    final class Coordinator {
        weak var view: SCNView?
        var didLoad = false

        /// Frame camera on the actual mesh so user sees the scan immediately (not empty sky).
        static func frameMesh(in view: SCNView, scene: SCNScene) {
            // Ensure materials visible
            scene.background.contents = UIColor.black
            PhotoTexturedMeshBuilder.normalizeForPreview(scene)

            let mesh = scene.rootNode.childNode(withName: "coloredMesh", recursively: true) ?? scene.rootNode

            // World-space bounds of all geometry
            var minV = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var maxV = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            var found = false
            func visit(_ n: SCNNode) {
                if let g = n.geometry {
                    let (bmin, bmax) = g.boundingBox
                    let corners: [SCNVector3] = [
                        SCNVector3(bmin.x, bmin.y, bmin.z), SCNVector3(bmax.x, bmin.y, bmin.z),
                        SCNVector3(bmin.x, bmax.y, bmin.z), SCNVector3(bmax.x, bmax.y, bmin.z),
                        SCNVector3(bmin.x, bmin.y, bmax.z), SCNVector3(bmax.x, bmin.y, bmax.z),
                        SCNVector3(bmin.x, bmax.y, bmax.z), SCNVector3(bmax.x, bmax.y, bmax.z),
                    ]
                    for c in corners {
                        let w = n.convertPosition(c, to: scene.rootNode)
                        if w.x.isFinite && w.y.isFinite && w.z.isFinite {
                            minV = simd_min(minV, SIMD3(w.x, w.y, w.z))
                            maxV = simd_max(maxV, SIMD3(w.x, w.y, w.z))
                            found = true
                        }
                    }
                }
                for c in n.childNodes { visit(c) }
            }
            visit(mesh)
            guard found else { return }

            // Full garage — camera stays OUTSIDE the box so you see the whole scan
            let cx = (minV.x + maxV.x) * 0.5
            let cy = (minV.y + maxV.y) * 0.5
            let cz = (minV.z + maxV.z) * 0.5
            let sx = max(maxV.x - minV.x, 0.4)
            let sy = max(maxV.y - minV.y, 0.4)
            let sz = max(maxV.z - minV.z, 0.4)
            let radius = max(max(sx, sy), sz) * 0.5
            let dist = radius * 2.45

            scene.rootNode.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }

            let cam = SCNNode()
            cam.name = "previewCam"
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 62
            cam.camera?.zNear = 0.05
            cam.camera?.zFar = Double(max(200, radius * 80))
            // High 3/4 corner — never spawn inside the room
            cam.position = SCNVector3(
                cx + dist * 0.72,
                maxV.y + radius * 0.35,
                cz + dist * 0.72
            )
            cam.look(at: SCNVector3(cx, cy, cz))
            scene.rootNode.addChildNode(cam)

            view.pointOfView = cam
            view.defaultCameraController.pointOfView = cam
            view.defaultCameraController.target = SCNVector3(cx, cy, cz)
            view.defaultCameraController.interactionMode = .orbitTurntable
            view.defaultCameraController.inertiaEnabled = true
            view.defaultCameraController.maximumVerticalAngle = 89
            view.defaultCameraController.minimumVerticalAngle = -80
            view.allowsCameraControl = true
            view.autoenablesDefaultLighting = true
            view.isPlaying = true
        }

        func load(url: URL, isLoading: Binding<Bool>, loadError: Binding<String?>) {
            guard !didLoad else { return }
            didLoad = true

            DispatchQueue.main.async {
                isLoading.wrappedValue = true
            }

            // Background load — large RoomPlan USDZ must not block UI
            DispatchQueue.global(qos: .userInitiated).async {
                // Sanity checks
                guard FileManager.default.fileExists(atPath: url.path) else {
                    DispatchQueue.main.async {
                        isLoading.wrappedValue = false
                        loadError.wrappedValue = "File missing:\n\(url.lastPathComponent)"
                    }
                    return
                }

                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                if size < 64 {
                    DispatchQueue.main.async {
                        isLoading.wrappedValue = false
                        loadError.wrappedValue = "Mesh file is empty. Scan again and save."
                    }
                    return
                }

                do {
                    // SceneKit loads USDZ reliably for preview (no RealityKit freeze)
                    let scene = try SCNScene(url: url, options: [
                        .checkConsistency: true,
                        .createNormalsIfAbsent: true,
                    ])

                    // Center + camera so mesh is always visible with real colors
                    PhotoTexturedMeshBuilder.normalizeForPreview(scene)

                    DispatchQueue.main.async { [weak self] in
                        guard let scnView = self?.view else { return }
                        scnView.scene = scene
                        Self.frameMesh(in: scnView, scene: scene)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            Self.frameMesh(in: scnView, scene: scene)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            Self.frameMesh(in: scnView, scene: scene)
                        }
                        scnView.defaultCameraController.inertiaEnabled = true
                        isLoading.wrappedValue = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        isLoading.wrappedValue = false
                        loadError.wrappedValue = error.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - System Quick Look fallback

struct QuickLookUSDZ: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Share

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
