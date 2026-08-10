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
            // Black voids like 3D Snap — photo mesh reads clearer
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color.black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text("Could not open mesh")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    if fileExists {
                        Button("Open in Quick Look") {
                            showQuickLook = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.blue)
                    }
                }
            } else if !fileExists {
                VStack(spacing: 16) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.blue)
                    Text("No USDZ file")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("This scan has no mesh on disk. Scan again and save.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            } else {
                MeshSceneView(
                    usdzURL: meshURL,
                    isLoading: $isLoading,
                    loadError: $loadError
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                        Text("Loading 3D mesh…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }

            VStack {
                Spacer()
                infoBar
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if fileExists {
                        Button {
                            showQuickLook = true
                        } label: {
                            Image(systemName: "eye")
                        }
                    }
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!fileExists)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: store.shareItems(for: session))
        }
        .sheet(isPresented: $showQuickLook) {
            QuickLookUSDZ(url: meshURL)
                .ignoresSafeArea()
        }
    }

    private var infoBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(isDenseMesh
                     ? "Full Space Mesh · \(session.wallCount) walls · \(session.objectCount) objects"
                     : "\(session.wallCount) walls · \(session.objectCount) objects · \(session.doorCount) doors")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text(isDenseMesh ? "Full Color Mesh" : "Structure")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isDenseMesh ? Color(red: 0.4, green: 0.9, blue: 0.7) : .white.opacity(0.7))
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding()
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
        /// Frame camera on the actual mesh so user sees the scan immediately (not empty sky).
        static func frameMesh(in view: SCNView, scene: SCNScene) {
            PhotoTexturedMeshBuilder.normalizeForPreview(scene)

            let mesh = scene.rootNode.childNode(withName: "coloredMesh", recursively: true) ?? scene.rootNode
            var minV = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var maxV = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            var found = false
            func visit(_ n: SCNNode) {
                if let g = n.geometry {
                    let (bmin, bmax) = g.boundingBox
                    for c in [SCNVector3(bmin.x, bmin.y, bmin.z), SCNVector3(bmax.x, bmax.y, bmax.z),
                              SCNVector3(bmin.x, bmax.y, bmin.z), SCNVector3(bmax.x, bmin.y, bmax.z)] {
                        let w = n.convertPosition(c, to: scene.rootNode)
                        minV = simd_min(minV, SIMD3(w.x, w.y, w.z))
                        maxV = simd_max(maxV, SIMD3(w.x, w.y, w.z))
                        found = true
                    }
                }
                for c in n.childNodes { visit(c) }
            }
            visit(mesh)
            guard found else { return }

            let center = SCNVector3(
                (minV.x + maxV.x) * 0.5,
                (minV.y + maxV.y) * 0.5,
                (minV.z + maxV.z) * 0.5
            )
            var radius = max(maxV.x - minV.x, max(maxV.y - minV.y, maxV.z - minV.z)) * 0.5
            radius = max(radius, 0.4)
            let dist = radius * 2.4

            scene.rootNode.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }

            let cam = SCNNode()
            cam.name = "previewCam"
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 50
            cam.camera?.zNear = 0.01
            cam.camera?.zFar = Double(max(120, radius * 40))
            // Look slightly above center so car/floor sit in the lower 2/3 (natural)
            cam.position = SCNVector3(center.x + dist * 0.55, center.y + dist * 0.35, center.z + dist * 0.9)
            let look = SCNLookAtConstraint(target: mesh)
            look.isGimbalLockEnabled = true
            cam.constraints = [look]
            scene.rootNode.addChildNode(cam)

            view.pointOfView = cam
            view.defaultCameraController.pointOfView = cam
            view.defaultCameraController.target = center
            view.defaultCameraController.interactionMode = .orbitTurntable
            view.allowsCameraControl = true
            view.autoenablesDefaultLighting = true
        }

        weak var view: SCNView?
        private var didLoad = false

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
