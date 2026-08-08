import SwiftUI
import SceneKit
import UIKit
import QuickLook

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
            // Soft studio bg
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.12, green: 0.16, blue: 0.28),
                    Color(red: 0.06, green: 0.08, blue: 0.12),
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
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
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

                    // Make materials show real surface colors (vertex colors / textures)
                    scene.rootNode.enumerateChildNodes { node, _ in
                        guard let geos = node.geometry else { return }
                        for mat in geos.materials {
                            mat.lightingModel = .physicallyBased
                            mat.isDoubleSided = true
                            mat.roughness.contents = NSNumber(value: 0.85)
                            mat.metalness.contents = NSNumber(value: 0.0)
                            // Keep existing diffuse/texture if present
                            if mat.diffuse.contents == nil {
                                mat.diffuse.contents = UIColor.white
                            }
                        }
                    }

                    // Soft ground only when not already a dense floor mesh
                    let floor = SCNFloor()
                    floor.reflectivity = 0.04
                    floor.firstMaterial?.diffuse.contents = UIColor(white: 0.12, alpha: 1)
                    floor.firstMaterial?.lightingModel = .physicallyBased
                    let floorNode = SCNNode(geometry: floor)
                    floorNode.position.y = -0.02
                    floorNode.name = "preview-floor"
                    scene.rootNode.addChildNode(floorNode)

                    if scene.rootNode.childNodes(passingTest: { n, _ in n.camera != nil }).isEmpty {
                        let cam = SCNNode()
                        cam.camera = SCNCamera()
                        cam.camera?.fieldOfView = 55
                        cam.camera?.wantsHDR = true
                        cam.position = SCNVector3(3.5, 2.4, 5.5)
                        cam.look(at: SCNVector3(0, 1.1, 0))
                        scene.rootNode.addChildNode(cam)
                    }

                    // Brighter, multi-light setup so room colors read as real
                    let key = SCNNode()
                    key.light = SCNLight()
                    key.light?.type = .directional
                    key.light?.intensity = 1000
                    key.light?.color = UIColor(white: 1.0, alpha: 1)
                    key.eulerAngles = SCNVector3(-0.85, 0.45, 0)
                    scene.rootNode.addChildNode(key)

                    let fill = SCNNode()
                    fill.light = SCNLight()
                    fill.light?.type = .directional
                    fill.light?.intensity = 450
                    fill.eulerAngles = SCNVector3(-0.3, -0.9, 0)
                    scene.rootNode.addChildNode(fill)

                    let ambient = SCNNode()
                    ambient.light = SCNLight()
                    ambient.light?.type = .ambient
                    ambient.light?.intensity = 500
                    ambient.light?.color = UIColor(white: 0.95, alpha: 1)
                    scene.rootNode.addChildNode(ambient)

                    DispatchQueue.main.async { [weak self] in
                        guard let scnView = self?.view else { return }
                        scnView.scene = scene
                        scnView.pointOfView = scene.rootNode.childNodes(passingTest: { n, _ in n.camera != nil }).first
                        // Default camera control target
                        scnView.defaultCameraController.automaticTarget = true
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
