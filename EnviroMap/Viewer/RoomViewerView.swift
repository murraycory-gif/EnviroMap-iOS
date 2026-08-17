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
        view.delegate = context.coordinator
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

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        weak var view: SCNView?
        var didLoad = false
        var lookTarget = SIMD3<Float>(0, 1, 0)

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let cam = renderer.pointOfView else { return }
            let camPos = SIMD3<Float>(cam.simdWorldPosition)
            let look = -SIMD3<Float>(cam.simdWorldFront)
            let lookLen = simd_length(look)
            guard lookLen > 1e-5 else { return }
            let lookDir = look / lookLen
            renderer.scene?.rootNode.enumerateChildNodes { node, _ in
                guard let name = node.name, name.hasPrefix("photoWall") else { return }
                let c = SIMD3<Float>(node.simdWorldPosition)
                let dist = simd_length(c - camPos)
                // Only hide a wall if the camera is sitting inside it
                node.isHidden = dist < 0.70
            }
        }

        /// Frame the whole scan from a 3/4 side view — never start on the ceiling.
        static func frameMesh(in view: SCNView, scene: SCNScene, coordinator: Coordinator? = nil) {
            scene.background.contents = UIColor.black
            PhotoTexturedMeshBuilder.normalizeForPreview(scene)

            let mesh = scene.rootNode.childNode(withName: "coloredMesh", recursively: true) ?? scene.rootNode

            var minAll = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var maxAll = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            var found = false
            var boxes: [(min: SIMD3<Float>, max: SIMD3<Float>, mid: SIMD3<Float>, isWall: Bool)] = []
            func visit(_ n: SCNNode) {
                if let g = n.geometry {
                    let (bmin, bmax) = g.boundingBox
                    let midL = SCNVector3(
                        (bmin.x + bmax.x) * 0.5,
                        (bmin.y + bmax.y) * 0.5,
                        (bmin.z + bmax.z) * 0.5
                    )
                    let wmid = n.convertPosition(midL, to: scene.rootNode)
                    var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                    var mx = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
                    let corners: [SCNVector3] = [
                        SCNVector3(bmin.x, bmin.y, bmin.z), SCNVector3(bmax.x, bmin.y, bmin.z),
                        SCNVector3(bmin.x, bmax.y, bmin.z), SCNVector3(bmax.x, bmax.y, bmin.z),
                        SCNVector3(bmin.x, bmin.y, bmax.z), SCNVector3(bmax.x, bmin.y, bmax.z),
                        SCNVector3(bmin.x, bmax.y, bmax.z), SCNVector3(bmax.x, bmax.y, bmax.z),
                    ]
                    for c in corners {
                        let w = n.convertPosition(c, to: scene.rootNode)
                        if w.x.isFinite && w.y.isFinite && w.z.isFinite {
                            mn = simd_min(mn, SIMD3(w.x, w.y, w.z))
                            mx = simd_max(mx, SIMD3(w.x, w.y, w.z))
                            found = true
                        }
                    }
                    if found {
                        minAll = simd_min(minAll, mn)
                        maxAll = simd_max(maxAll, mx)
                        boxes.append((mn, mx, SIMD3(wmid.x, wmid.y, wmid.z), (n.name ?? "").hasPrefix("photoWall")))
                    }
                }
                for c in n.childNodes { visit(c) }
            }
            visit(mesh)
            guard found else { return }

            let cx = (minAll.x + maxAll.x) * 0.5
            let cy = (minAll.y + maxAll.y) * 0.5
            let cz = (minAll.z + maxAll.z) * 0.5
            let sx = max(maxAll.x - minAll.x, 0.6)
            let sy = max(maxAll.y - minAll.y, 0.6)
            let sz = max(maxAll.z - minAll.z, 0.6)

            var lookSum = SIMD3<Float>(0, 0, 0)
            var lookN: Float = 0
            let yLo = minAll.y + sy * 0.22
            let yHi = minAll.y + sy * 0.62
            for b in boxes where !b.isWall {
                if b.mid.y >= yLo && b.mid.y <= yHi {
                    lookSum += b.mid
                    lookN += 1
                }
            }
            var lx = cx, ly = cy, lz = cz
            if lookN > 2 {
                lx = lookSum.x / lookN
                ly = lookSum.y / lookN
                lz = lookSum.z / lookN
            }
            ly = min(max(ly, minAll.y + sy * 0.28), minAll.y + sy * 0.52)

            let horiz = max(sx, sz)
            let dist = max(horiz * 0.95, sy * 1.15)
            // Stand at chest height, 3/4 side — this is the “I can see the car” view
            let camY = min(ly + 0.85, maxAll.y - 0.15)
            let cam = SCNNode()
            cam.name = "previewCam"
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 50
            cam.camera?.zNear = 0.05
            cam.camera?.zFar = Double(max(200, horiz * 40))
            cam.position = SCNVector3(
                lx + dist * 0.78,
                camY,
                lz + dist * 0.52
            )
            cam.look(at: SCNVector3(lx, ly, lz))
            coordinator?.lookTarget = SIMD3(lx, ly, lz)

            scene.rootNode.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }
            scene.rootNode.addChildNode(cam)

            view.pointOfView = cam
            view.defaultCameraController.pointOfView = cam
            view.defaultCameraController.target = SCNVector3(lx, ly, lz)
            view.defaultCameraController.interactionMode = .orbitTurntable
            view.defaultCameraController.inertiaEnabled = true
            view.defaultCameraController.maximumVerticalAngle = 80
            view.defaultCameraController.minimumVerticalAngle = -25
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
                        Self.frameMesh(in: scnView, scene: scene, coordinator: self)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            Self.frameMesh(in: scnView, scene: scene, coordinator: self)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            Self.frameMesh(in: scnView, scene: scene, coordinator: self)
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
