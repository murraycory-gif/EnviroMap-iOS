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

                // Mesh card
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.radiusL, style: .continuous)
                        .fill(AppTheme.card)
                        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)

                    if let scene = model.previewScene {
                        PreviewMeshView(scene: scene)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusL, style: .continuous))
                    } else if let url = model.previewMeshURL {
                        PreviewMeshView(url: url)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusL, style: .continuous))
                    } else {
                        ProgressView()
                            .tint(AppTheme.blue)
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Label("Drag · Pinch", systemImage: "hand.draw")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                            Spacer()
                            Text("Full Color Mesh")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.blueSoft, in: Capsule())
                        }
                        .padding(14)
                    }
                }
                .padding(.horizontal, 16)
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

    init(scene: SCNScene) {
        self.scene = scene
        self.url = nil
    }

    init(url: URL) {
        self.url = url
        self.scene = nil
    }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X

        if let scene {
            prepare(scene)
            v.scene = scene
            v.defaultCameraController.automaticTarget = true
            v.defaultCameraController.inertiaEnabled = true
            return v
        }

        if let url {
            DispatchQueue.global(qos: .userInitiated).async {
                // Load atlas next to scn if present
                let atlasPath = url.deletingLastPathComponent().appendingPathComponent("atlas.png").path
                if let scene = try? SCNScene(url: url, options: nil) {
                    // Re-apply atlas texture from file (survives export)
                    if FileManager.default.fileExists(atPath: atlasPath) {
                        scene.rootNode.enumerateChildNodes { node, _ in
                            guard let mats = node.geometry?.materials else { return }
                            for mat in mats {
                                mat.lightingModel = .constant
                                mat.isDoubleSided = true
                                mat.diffuse.contents = atlasPath
                                mat.diffuse.magnificationFilter = .nearest
                                mat.diffuse.minificationFilter = .nearest
                            }
                        }
                    } else {
                        prepare(scene)
                    }
                    DispatchQueue.main.async {
                        v.scene = scene
                        v.defaultCameraController.automaticTarget = true
                        v.defaultCameraController.inertiaEnabled = true
                    }
                }
            }
        }
        return v
    }

    private func prepare(_ scene: SCNScene) {
        scene.background.contents = UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let mats = node.geometry?.materials else { return }
            for mat in mats {
                mat.lightingModel = .constant
                mat.isDoubleSided = true
                mat.shaderModifiers = [:]
            }
        }
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
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
        instruction = "Yellow dots = tracking. Mesh number rises as surfaces are saved. Get close and circle each item."
        controller.onStats = { [weak self] chunks, frames in
            Task { @MainActor in
                self?.meshChunks = chunks
                self?.hasColorFrames = frames > 0
                self?.coverageLabel = chunks > 40 ? "Good" : chunks > 15 ? "OK" : "Low"
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
        instruction = "Building full-color 3D mesh…"
        controller.stopCapturing()
        // Extra final harvest after a brief settle
        previewImage = controller.snapshot()
        controller.forceFinalHarvest()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.controller.buildExport()
            DispatchQueue.main.async {
                if let result {
                    self.exportPayload = result
                    self.previewMeshURL = result.directory.appendingPathComponent(result.fileName)
                    self.previewScene = result.scene
                    self.phase = .preview
                    self.statusTitle = "Review"
                    self.instruction = "Inspect your full-color scan, then save."
                    self.controller.stop()
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

final class FullEnvScanController: UIViewController, ARSessionDelegate {
    private var arView: ARSCNView!
    private var isRunning = false

    private let stateLock = NSLock()
    /// Copied geometry only — never keep live ARMeshAnchor refs long-term
    private var chunks: [UUID: CapturedMeshChunk] = [:]
    private var keyframes: [PhotoTexturedMeshBuilder.Keyframe] = []
    private var lastKeyframeTime: TimeInterval = 0
    private var lastMeshCopyTime: TimeInterval = 0
    private var lastStatsEmit: TimeInterval = 0
    private let maxKeyframes = 80
    private let maxChunks = 600
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
        // Yellow feature points = live proof of tracking / capture
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
        // Final mesh pull while session still live
        if let frame = arView?.session.currentFrame {
            ingestMeshes(from: frame)
            ingestKeyframe(from: frame)
        }
    }

    func stop() {
        isRunning = false
        arView?.session.pause()
    }

    func snapshot() -> UIImage? { arView?.snapshot() }

    func forceFinalHarvest() {
        if let frame = arView?.session.currentFrame {
            ingestMeshes(from: frame)
            ingestKeyframe(from: frame)
        }
    }

    func buildExport() -> FullEnvironmentScanModel.ExportPayload? {
        stateLock.lock()
        let meshChunks = Array(chunks.values)
        let frames = keyframes
        stateLock.unlock()

        guard !meshChunks.isEmpty else { return nil }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnviroMapFull_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Single build: in-memory colored scene + atlas.png + scn on disk
        guard let scene = PhotoTexturedMeshBuilder.makeScene(chunks: meshChunks, keyframes: frames) else {
            return nil
        }
        // Write atlas + scn for permanent save
        _ = PhotoTexturedMeshBuilder.exportChunks(meshChunks, keyframes: frames, to: tmp)
        return .init(directory: tmp, fileName: "room_full.scn", scene: scene)
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning else { return }
        let t = frame.timestamp

        // Copy mesh from frame anchors (throttled) — safe snapshot
        if t - lastMeshCopyTime >= 0.12 {
            lastMeshCopyTime = t
            ingestMeshes(from: frame)
        }

        // Color keyframes (throttled)
        if t - lastKeyframeTime >= 0.16 {
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
        if now - lastMarkerUpdate < 0.6 { return }
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
            maxWidth: 512
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

        // Cap per-chunk vertices to avoid memory spikes
        guard vCount < 200_000 else { return nil }

        var positions = [SIMD3<Float>](repeating: .zero, count: vCount)
        var normals = [SIMD3<Float>](repeating: .zero, count: vCount)
        for i in 0..<vCount {
            let vp = vSource.buffer.contents().advanced(by: vSource.offset + vSource.stride * i)
            positions[i] = vp.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            if nSource.count == vCount {
                let np = nSource.buffer.contents().advanced(by: nSource.offset + nSource.stride * i)
                normals[i] = np.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            }
        }

        var indices = [UInt32]()
        indices.reserveCapacity(faces.count * faces.indexCountPerPrimitive)
        for f in 0..<faces.count {
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
