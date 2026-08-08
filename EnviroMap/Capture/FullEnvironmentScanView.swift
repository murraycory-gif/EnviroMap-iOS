import SwiftUI
import ARKit
import SceneKit
import UIKit
import AVFoundation

/// Full-environment LiDAR scan with real camera colors + review-before-save.
struct FullEnvironmentScanView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = FullEnvironmentScanModel()
    @State private var name: String = ""
    @State private var saveError: String?
    @State private var didSave = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.08, blue: 0.14).ignoresSafeArea()

            switch model.phase {
            case .idle, .scanning, .processing, .failed:
                scanCameraLayer
            case .preview, .saving:
                previewLayer
            }
        }
        .preferredColorScheme(model.phase == .preview || model.phase == .saving ? .light : .dark)
        .onAppear {
            if name.isEmpty { name = defaultName() }
            model.start()
        }
        .onDisappear { model.stop() }
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Live scan

    private var scanCameraLayer: some View {
        ZStack {
            FullEnvARContainer(model: model)
                .ignoresSafeArea()

            // Soft edge vignette so camera stays readable (no heavy mesh overlay)
            VStack(spacing: 0) {
                scanTopBar
                Spacer()
                scanBottomBar
            }
        }
    }

    private var scanTopBar: some View {
        HStack {
            Button {
                model.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text(model.statusTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(model.detailLine)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Full Env · Real Colors")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.7))
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var scanBottomBar: some View {
        VStack(spacing: 12) {
            Text(model.instruction)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Live capture status
            if model.phase == .scanning {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text(model.meshChunks > 0
                         ? "Capturing… \(model.meshChunks) surfaces saved"
                         : "Point at a surface to start capturing")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.45), in: Capsule())
            }

            HStack(spacing: 10) {
                metric("Mesh", "\(model.meshChunks)")
                metric("Coverage", model.coverageLabel)
                metric("Color", model.hasColorFrames ? "On" : "…")
            }

            Group {
                switch model.phase {
                case .scanning:
                    Button {
                        model.finishScanning()
                    } label: {
                        Label("Done — Review Scan", systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.blue)
                    .disabled(model.meshChunks < 2)

                case .processing:
                    HStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Baking Real Colors Onto Mesh…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                case .failed(let msg):
                    VStack(spacing: 12) {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { model.start() }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.blue)
                    }

                default:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private func viewControl(icon: String, title: String, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Preview before save (light AppTheme design)

    private var previewLayer: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            // Soft blue wash like Home
            LinearGradient(
                colors: [
                    AppTheme.blue.opacity(0.10),
                    AppTheme.bg,
                    AppTheme.blueSoft.opacity(0.35),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button {
                        model.rescan()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Rescan")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.blue)
                    }
                    Spacer()
                    Text("Review Scan")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                    Spacer()
                    Color.clear.frame(width: 64)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Large 3D viewer
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.radiusL, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)

                    if let scene = model.previewScene {
                        PreviewMeshView(scene: scene, resetToken: model.viewResetToken)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusL, style: .continuous))
                    } else if let url = model.previewMeshURL {
                        PreviewMeshView(url: url, resetToken: model.viewResetToken)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusL, style: .continuous))
                    } else {
                        ProgressView()
                            .tint(AppTheme.blue)
                    }

                    VStack {
                        HStack {
                            Spacer()
                            Text("Full Color")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.blue.opacity(0.9), in: Capsule())
                        }
                        .padding(12)
                        Spacer()
                        // Controls
                        HStack(spacing: 10) {
                            viewControl(icon: "arrow.triangle.2.circlepath", title: "Reset") {
                                model.viewResetToken += 1
                            }
                            viewControl(icon: "hand.draw.fill", title: "Drag Spin")
                            viewControl(icon: "arrow.up.left.and.arrow.down.right", title: "Pinch Zoom")
                        }
                        .padding(12)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)

                // Bottom save card
                VStack(alignment: .leading, spacing: 14) {
                    Text("Looks Good?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.text)

                    Text("Check the colors and coverage. Rescan if there are big holes, or save to My Rooms.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                        TextField("Room Name", text: $name)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                                    .fill(AppTheme.bg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                                    .stroke(AppTheme.cardBorder, lineWidth: 1)
                            )
                            .foregroundStyle(AppTheme.text)
                    }

                    HStack(spacing: 12) {
                        Button {
                            model.rescan()
                        } label: {
                            Text("Rescan")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                                        .stroke(AppTheme.blue.opacity(0.35), lineWidth: 1.5)
                                )
                        }

                        Button {
                            save()
                        } label: {
                            Group {
                                if model.phase == .saving {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Save To My Rooms")
                                        .font(.headline.weight(.bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [AppTheme.blue, AppTheme.blueDeep],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                            )
                        }
                        .disabled(didSave || model.phase == .saving)
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(AppTheme.card)
                        .shadow(color: .black.opacity(0.08), radius: 20, y: -2)
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.light)
    }

    private func save() {
        guard let payload = model.exportPayload else {
            saveError = "No mesh to save. Scan again."
            return
        }
        model.phase = .saving
        // Ensure scn is on disk (Review may have shown before write finished)
        let scnURL = payload.directory.appendingPathComponent(payload.fileName)
        if !FileManager.default.fileExists(atPath: scnURL.path), let scene = payload.scene {
            _ = PhotoTexturedMeshBuilder.writeScene(scene, to: payload.directory, name: payload.fileName)
        }
        do {
            _ = try store.saveFullEnvironment(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: "Full environment LiDAR + photo color",
                meshFileName: payload.fileName,
                sourceDirectory: payload.directory,
                preview: model.previewImage,
                meshChunkCount: model.meshChunks
            )
            didSave = true
            model.stop()
            dismiss()
        } catch {
            model.phase = .preview
            saveError = error.localizedDescription
        }
    }

    private func defaultName() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return "Space \(f.string(from: Date()))"
    }
}

// MARK: - Preview SCNView

struct PreviewMeshView: UIViewRepresentable {
    var scene: SCNScene? = nil
    var url: URL? = nil
    var resetToken: Int = 0

    init(scene: SCNScene, resetToken: Int = 0) {
        self.scene = scene
        self.url = nil
        self.resetToken = resetToken
    }

    init(url: URL, resetToken: Int = 0) {
        self.url = url
        self.scene = nil
        self.resetToken = resetToken
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        // Natural orbit (turntable) — easier than free camera
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.defaultCameraController.maximumVerticalAngle = 85
        v.defaultCameraController.minimumVerticalAngle = -10
        context.coordinator.scnView = v

        if let scene {
            prepare(scene)
            v.scene = scene
            context.coordinator.fitCamera(in: v, scene: scene)
        } else if let url {
            DispatchQueue.global(qos: .userInitiated).async {
                if let scene = try? SCNScene(url: url, options: nil) {
                    prepare(scene)
                    DispatchQueue.main.async {
                        v.scene = scene
                        context.coordinator.fitCamera(in: v, scene: scene)
                    }
                }
            }
        }
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if context.coordinator.lastReset != resetToken {
            context.coordinator.lastReset = resetToken
            if let scene = uiView.scene {
                context.coordinator.fitCamera(in: uiView, scene: scene)
            }
        }
    }

    private func prepare(_ scene: SCNScene) {
        scene.background.contents = UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1)
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let mats = node.geometry?.materials else { return }
            for mat in mats {
                // Keep colors; lambert shows form
                if mat.lightingModel != .lambert {
                    mat.lightingModel = .lambert
                }
                mat.isDoubleSided = true
                mat.shaderModifiers = [:]
            }
        }
    }

    final class Coordinator {
        var scnView: SCNView?
        var lastReset: Int = -1

        func fitCamera(in view: SCNView, scene: SCNScene) {
            // Prefer mesh root bounds
            let target = scene.rootNode.childNode(withName: "coloredMesh", recursively: true) ?? scene.rootNode
            let (minB, maxB) = target.boundingBox
            let center = SCNVector3(
                (minB.x + maxB.x) * 0.5,
                (minB.y + maxB.y) * 0.5,
                (minB.z + maxB.z) * 0.5
            )
            let dx = maxB.x - minB.x
            let dy = maxB.y - minB.y
            let dz = maxB.z - minB.z
            let radius = max(max(dx, dy), dz) * 0.55
            let dist = max(CGFloat(radius) * 2.4, 0.8)

            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 50
            cam.camera?.zNear = 0.01
            cam.camera?.zFar = 500
            cam.position = SCNVector3(
                center.x + Float(dist) * 0.45,
                center.y + Float(dist) * 0.35,
                center.z + Float(dist) * 0.85
            )
            // Aim at center without look(at:) API variance
            let dxp = center.x - cam.position.x
            let dyp = center.y - cam.position.y
            let dzp = center.z - cam.position.z
            let yaw = atan2(dxp, dzp)
            let pitch = -atan2(dyp, sqrt(dxp * dxp + dzp * dzp))
            cam.eulerAngles = SCNVector3(pitch, yaw, 0)

            // Replace old camera nodes named previewCam
            scene.rootNode.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }
            scene.rootNode.addChildNode(cam)
            view.pointOfView = cam

            view.defaultCameraController.target = center
            view.defaultCameraController.inertiaEnabled = true
        }
    }
}

// MARK: - Model

@MainActor
final class FullEnvironmentScanModel: ObservableObject {
    enum Phase: Equatable {
        case idle, scanning, processing, preview, saving, failed(String)
    }

    struct ExportPayload {
        let directory: URL
        let fileName: String
        let scene: SCNScene?
    }

    @Published var phase: Phase = .idle
    @Published var instruction = "Move slowly. Cover everything you want in 3D."
    @Published var statusTitle = "Full 3D Scan"
    @Published var detailLine = "LiDAR + real colors"
    @Published var meshChunks = 0
    @Published var coverageLabel = "—"
    @Published var hasColorFrames = false
    @Published var previewImage: UIImage?
    @Published var exportPayload: ExportPayload?
    @Published var previewMeshURL: URL?
    @Published var previewScene: SCNScene?
    @Published var viewResetToken: Int = 0

    let controller = FullEnvScanController()

    func start() {
        exportPayload = nil
        previewMeshURL = nil
        previewScene = nil
        meshChunks = 0
        hasColorFrames = false
        coverageLabel = "—"
        phase = .scanning
        statusTitle = "Scanning"
        instruction = "Move slowly. Yellow dots = tracking. Mesh count rises as space is saved."
        controller.onStats = { [weak self] chunks, frames in
            Task { @MainActor in
                self?.meshChunks = chunks
                self?.hasColorFrames = frames > 0
                self?.coverageLabel = chunks > 80 ? "Great" : chunks > 35 ? "Good" : chunks > 12 ? "OK" : "Low"
                self?.detailLine = "\(chunks) mesh pieces · \(frames) color frames"
            }
        }
        controller.onError = { [weak self] msg in
            Task { @MainActor in
                self?.phase = .failed(msg)
            }
        }
        controller.start()
    }

    func stop() { controller.stop() }

    func rescan() {
        controller.stop()
        start()
    }

    func finishScanning() {
        guard phase == .scanning else { return }
        phase = .processing
        statusTitle = "Processing"
        instruction = "Building your 3D view…"
        controller.stopCapturing()
        previewImage = controller.snapshot()
        controller.forceFinalHarvest()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // Build scene only first (fast path to Review)
            let result = self.controller.buildExportFast()
            DispatchQueue.main.async {
                if let result {
                    self.exportPayload = result
                    self.previewMeshURL = result.directory.appendingPathComponent(result.fileName)
                    self.previewScene = result.scene
                    self.phase = .preview
                    self.statusTitle = "Review"
                    self.instruction = "Drag to spin · Pinch to zoom"
                    self.controller.stop()
                    // Write file in background so Save is ready without blocking UI
                    self.controller.persistExportInBackground(result)
                } else {
                    self.phase = .failed("Not enough mesh. Scan longer and cover more surfaces.")
                }
            }
        }
    }
}

// MARK: - AR container

struct FullEnvARContainer: UIViewControllerRepresentable {
    @ObservedObject var model: FullEnvironmentScanModel
    func makeUIViewController(context: Context) -> FullEnvScanController { model.controller }
    func updateUIViewController(_ uiViewController: FullEnvScanController, context: Context) {}
}

// MARK: - Copied mesh (safe after ARKit invalidates anchors)

struct CapturedMeshChunk {
    let id: UUID
    let transform: simd_float4x4
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
}

// MARK: - ARKit controller (stable long scans)

final class FullEnvScanController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    private var arView: ARSCNView!
    private var isRunning = false

    private let stateLock = NSLock()
    /// Copied geometry only — never keep live ARMeshAnchor refs long-term
    private var chunks: [UUID: CapturedMeshChunk] = [:]
    private var keyframes: [PhotoTexturedMeshBuilder.Keyframe] = []
    private var lastKeyframeTime: TimeInterval = 0
    private var lastMeshCopyTime: TimeInterval = 0
    private var lastStatsEmit: TimeInterval = 0
    private let maxKeyframes = 36
    private let maxChunks = 500
    private var coverageRoot: SCNNode?
    private var lastMarkerUpdate: TimeInterval = 0

    var onStats: ((Int, Int) -> Void)?
    var onError: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Camera only — no SceneKit mesh rebuilds (those froze long scans)
        let scn = ARSCNView(frame: view.bounds)
        scn.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scn.session.delegate = self
        scn.automaticallyUpdatesLighting = true
        scn.scene = SCNScene()
        scn.rendersCameraGrain = false
        scn.delegate = self
        // Yellow feature points + we'll add blue mesh lines for coverage
        scn.debugOptions = [.showFeaturePoints]
        view.addSubview(scn)
        arView = scn
        let root = SCNNode()
        root.name = "coverageRoot"
        scn.scene.rootNode.addChildNode(root)
        coverageRoot = root
    }

    func start() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
                || ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            onError?("This device cannot build a LiDAR mesh.")
            return
        }

        stateLock.lock()
        chunks.removeAll()
        keyframes.removeAll()
        lastKeyframeTime = 0
        lastMeshCopyTime = 0
        lastStatsEmit = 0
        lastMarkerUpdate = 0
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.coverageRoot?.childNodes.forEach { $0.removeFromParentNode() }
        }

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else {
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        isRunning = true
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopCapturing() {
        isRunning = false
        forceFinalHarvest()
    }

    func stop() {
        isRunning = false
        arView?.session.pause()
    }

    func snapshot() -> UIImage? { arView?.snapshot() }

    func forceFinalHarvest() {
        // Multiple pulls while session still has dense mesh anchors
        if let frame = arView?.session.currentFrame {
            ingestMeshes(from: frame)
            ingestKeyframe(from: frame)
        }
        // Also scrape any ARMeshAnchors still tracked by the session
        if let anchors = arView?.session.currentFrame?.anchors {
            for a in anchors {
                guard let mesh = a as? ARMeshAnchor else { continue }
                if let chunk = Self.copyChunk(from: mesh) {
                    stateLock.lock()
                    chunks[chunk.id] = chunk
                    stateLock.unlock()
                }
            }
        }
    }

    func buildExportFast() -> FullEnvironmentScanModel.ExportPayload? {
        stateLock.lock()
        let meshChunks = Array(chunks.values)
        let frames = keyframes
        stateLock.unlock()

        guard !meshChunks.isEmpty else { return nil }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnviroMapFull_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Build photo-textured scene once (writes tex_*.jpg into tmp when dir provided via export)
        // Fast path: makeScene without writing files; textures stay in memory for Review
        guard let scene = PhotoTexturedMeshBuilder.makeScene(chunks: meshChunks, keyframes: frames) else {
            return nil
        }
        return .init(directory: tmp, fileName: "room_full.scn", scene: scene)
    }

    /// Full export with texture files + scn (background after Review appears).
    func persistExportInBackground(_ payload: FullEnvironmentScanModel.ExportPayload) {
        stateLock.lock()
        let meshChunks = Array(chunks.values)
        let frames = keyframes
        stateLock.unlock()
        let dir = payload.directory
        DispatchQueue.global(qos: .utility).async {
            // Rebuild with textureDir so jpg textures are saved next to scn
            if let built = PhotoTexturedMeshBuilder.buildAndExport(
                chunks: meshChunks,
                keyframes: frames,
                to: dir
            ) {
                _ = built
            } else if let scene = payload.scene {
                _ = PhotoTexturedMeshBuilder.writeScene(scene, to: dir)
            }
        }
    }


    // MARK: - Live blue mesh (throttled — better coverage feedback)

    private var lastVizTime: [UUID: TimeInterval] = [:]

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARMeshAnchor else { return nil }
        return SCNNode()
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        applyBlueWire(node: node, mesh: mesh)
        // Also copy into our safe store
        if let chunk = Self.copyChunk(from: mesh) {
            stateLock.lock()
            chunks[chunk.id] = chunk
            let mc = chunks.count
            let fc = keyframes.count
            stateLock.unlock()
            emitStats(meshCount: mc, frameCount: fc)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        let now = CACurrentMediaTime()
        if let last = lastVizTime[mesh.identifier], now - last < 0.55 { return }
        lastVizTime[mesh.identifier] = now
        applyBlueWire(node: node, mesh: mesh)
        if let chunk = Self.copyChunk(from: mesh) {
            stateLock.lock()
            chunks[chunk.id] = chunk
            let mc = chunks.count
            let fc = keyframes.count
            stateLock.unlock()
            emitStats(meshCount: mc, frameCount: fc)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        lastVizTime.removeValue(forKey: anchor.identifier)
        stateLock.lock()
        chunks.removeValue(forKey: anchor.identifier)
        stateLock.unlock()
    }

    private func applyBlueWire(node: SCNNode, mesh: ARMeshAnchor) {
        // Lightweight: skip full wire rebuild (was main scan lag).
        // User still sees yellow feature points + cyan coverage dots.
        _ = mesh
        _ = node
    }

    private static func wireGeometry(_ mesh: ARMeshGeometry) -> SCNGeometry? {
        let vCount = mesh.vertices.count
        guard vCount > 0, mesh.faces.count > 0, vCount < 120_000 else { return nil }
        var positions = [Float](repeating: 0, count: vCount * 3)
        for i in 0..<vCount {
            let p = mesh.vertices.buffer.contents()
                .advanced(by: mesh.vertices.offset + mesh.vertices.stride * i)
                .assumingMemoryBound(to: SIMD3<Float>.self).pointee
            positions[i * 3] = p.x
            positions[i * 3 + 1] = p.y
            positions[i * 3 + 2] = p.z
        }
        let posData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let source = SCNGeometrySource(
            data: posData, semantic: .vertex, vectorCount: vCount,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        var indices = [UInt32]()
        let faces = mesh.faces
        // Only take every other triangle for lighter wireframe
        for f in stride(from: 0, to: faces.count, by: 1) {
            for c in 0..<faces.indexCountPerPrimitive {
                let off = (f * faces.indexCountPerPrimitive + c) * faces.bytesPerIndex
                let base = faces.buffer.contents().advanced(by: off)
                if faces.bytesPerIndex == 2 {
                    indices.append(UInt32(base.assumingMemoryBound(to: UInt16.self).pointee))
                } else {
                    indices.append(base.assumingMemoryBound(to: UInt32.self).pointee)
                }
            }
        }
        guard !indices.isEmpty else { return nil }
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: indices.count / 3, bytesPerIndex: 4
        )
        let geom = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.fillMode = .lines
        mat.diffuse.contents = UIColor(red: 0.25, green: 0.75, blue: 1.0, alpha: 0.95)
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        geom.materials = [mat]
        return geom
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning else { return }
        let t = frame.timestamp

        // Copy mesh from frame anchors (throttled) — safe snapshot
        if t - lastMeshCopyTime >= 0.20 {
            lastMeshCopyTime = t
            ingestMeshes(from: frame)
        }

        // Color keyframes (throttled)
        if t - lastKeyframeTime >= 0.28 {
            lastKeyframeTime = t
            ingestKeyframe(from: frame)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error.localizedDescription)
        }
    }

    private func ingestMeshes(from frame: ARFrame) {
        var copied: [CapturedMeshChunk] = []
        for anchor in frame.anchors {
            guard let mesh = anchor as? ARMeshAnchor else { continue }
            if let chunk = Self.copyChunk(from: mesh) {
                copied.append(chunk)
            }
        }
        guard !copied.isEmpty else { return }

        stateLock.lock()
        for c in copied {
            // Always keep latest geometry for each mesh tile (updates fill holes)
            chunks[c.id] = c
        }
        // Only drop if extreme (protects memory); prefer completeness
        if chunks.count > maxChunks {
            // Drop smallest chunks first (least detail), not oldest scanned areas
            let ranked = chunks.values.sorted { $0.positions.count < $1.positions.count }
            let removeCount = chunks.count - maxChunks
            for i in 0..<removeCount {
                chunks.removeValue(forKey: ranked[i].id)
            }
        }
        let meshCount = chunks.count
        let frameCount = keyframes.count
        stateLock.unlock()

        emitStats(meshCount: meshCount, frameCount: frameCount)
        updateCoverageMarkersIfNeeded()
    }

    /// Lightweight dots so user SEES capture progress (not heavy wireframe).
    private func updateCoverageMarkersIfNeeded() {
        let now = CACurrentMediaTime()
        if now - lastMarkerUpdate < 1.2 { return }
        lastMarkerUpdate = now

        stateLock.lock()
        let snapshot = Array(chunks.values)
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self, let root = self.coverageRoot else { return }
            root.childNodes.forEach { $0.removeFromParentNode() }

            // Show up to 80 markers for performance
            let step = max(1, snapshot.count / 80)
            var i = 0
            while i < snapshot.count {
                let c = snapshot[i]
                // World-space center
                var center = SIMD3<Float>(0, 0, 0)
                let n = max(c.positions.count, 1)
                for p in c.positions {
                    let w = c.transform * SIMD4<Float>(p.x, p.y, p.z, 1)
                    center += SIMD3<Float>(w.x, w.y, w.z)
                }
                center /= Float(n)

                let sphere = SCNSphere(radius: 0.025)
                let mat = SCNMaterial()
                mat.lightingModel = .constant
                mat.diffuse.contents = UIColor(red: 0.15, green: 0.75, blue: 1.0, alpha: 0.95)
                sphere.materials = [mat]
                let node = SCNNode(geometry: sphere)
                node.simdPosition = center
                root.addChildNode(node)
                i += step
            }
        }
    }

    private func ingestKeyframe(from frame: ARFrame) {
        let orientation: UIInterfaceOrientation = .portrait
        let viewport = arView?.bounds.size ?? CGSize(width: 390, height: 844)
        guard let kf = PhotoTexturedMeshBuilder.makeKeyframe(
            from: frame,
            orientation: orientation,
            viewport: viewport,
            maxWidth: 400
        ) else { return }

        stateLock.lock()
        keyframes.append(kf)
        if keyframes.count > maxKeyframes {
            keyframes.removeFirst(keyframes.count - maxKeyframes)
        }
        let meshCount = chunks.count
        let frameCount = keyframes.count
        stateLock.unlock()

        emitStats(meshCount: meshCount, frameCount: frameCount)
    }

    private func emitStats(meshCount: Int, frameCount: Int) {
        let now = CACurrentMediaTime()
        if now - lastStatsEmit < 0.25 { return }
        lastStatsEmit = now
        DispatchQueue.main.async { [weak self] in
            self?.onStats?(meshCount, frameCount)
        }
    }

    /// Deep-copy mesh buffers while the anchor is valid (during this callback only).
    private static func copyChunk(from anchor: ARMeshAnchor) -> CapturedMeshChunk? {
        let geom = anchor.geometry
        let vSource = geom.vertices
        let nSource = geom.normals
        let faces = geom.faces
        let vCount = vSource.count
        guard vCount > 0, faces.count > 0 else { return nil }
        // Soft cap — skip only extreme anchors
        guard vCount < 100_000 else { return nil }

        // Subsample large meshes for smoother scanning / faster bake
        let step = vCount > 25_000 ? 2 : 1
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(vCount / step + 1)
        normals.reserveCapacity(vCount / step + 1)
        var remap = [Int: Int]()
        remap.reserveCapacity(vCount / step + 1)

        for i in stride(from: 0, to: vCount, by: step) {
            let vp = vSource.buffer.contents().advanced(by: vSource.offset + vSource.stride * i)
            positions.append(vp.assumingMemoryBound(to: SIMD3<Float>.self).pointee)
            if nSource.count == vCount {
                let np = nSource.buffer.contents().advanced(by: nSource.offset + nSource.stride * i)
                normals.append(np.assumingMemoryBound(to: SIMD3<Float>.self).pointee)
            } else {
                normals.append(SIMD3(0, 1, 0))
            }
            remap[i] = positions.count - 1
        }

        var indices = [UInt32]()
        let faceStep = faces.count > 40_000 ? 2 : 1
        indices.reserveCapacity(faces.count / faceStep * faces.indexCountPerPrimitive)
        for f in stride(from: 0, to: faces.count, by: faceStep) {
            var tri = [UInt32]()
            tri.reserveCapacity(3)
            var ok = true
            for c in 0..<faces.indexCountPerPrimitive {
                let off = (f * faces.indexCountPerPrimitive + c) * faces.bytesPerIndex
                let base = faces.buffer.contents().advanced(by: off)
                let raw: Int
                if faces.bytesPerIndex == 2 {
                    raw = Int(base.assumingMemoryBound(to: UInt16.self).pointee)
                } else {
                    raw = Int(base.assumingMemoryBound(to: UInt32.self).pointee)
                }
                let snapped = (raw / step) * step
                guard let mapped = remap[snapped] else { ok = false; break }
                tri.append(UInt32(mapped))
            }
            if ok, tri.count == 3, tri[0] != tri[1], tri[1] != tri[2] {
                indices.append(contentsOf: tri)
            }
        }
        guard !indices.isEmpty else { return nil }

        return CapturedMeshChunk(
            id: anchor.identifier,
            transform: anchor.transform,
            positions: positions,
            normals: normals,
            indices: indices
        )
    }

    private static func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)
        var copy: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attrs as CFDictionary, &copy) == kCVReturnSuccess,
              let copy else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }

        let planeCount = CVPixelBufferGetPlaneCount(source)
        if planeCount > 0 {
            for plane in 0..<planeCount {
                guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dst = CVPixelBufferGetBaseAddressOfPlane(copy, plane) else { continue }
                let h = CVPixelBufferGetHeightOfPlane(source, plane)
                let srcBytes = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dstBytes = CVPixelBufferGetBytesPerRowOfPlane(copy, plane)
                let row = min(srcBytes, dstBytes)
                for y in 0..<h {
                    memcpy(dst.advanced(by: y * dstBytes), src.advanced(by: y * srcBytes), row)
                }
            }
        } else if let src = CVPixelBufferGetBaseAddress(source),
                  let dst = CVPixelBufferGetBaseAddress(copy) {
            let h = CVPixelBufferGetHeight(source)
            let srcBytes = CVPixelBufferGetBytesPerRow(source)
            let dstBytes = CVPixelBufferGetBytesPerRow(copy)
            let row = min(srcBytes, dstBytes)
            for y in 0..<h {
                memcpy(dst.advanced(by: y * dstBytes), src.advanced(by: y * srcBytes), row)
            }
        }
        return copy
    }
}
