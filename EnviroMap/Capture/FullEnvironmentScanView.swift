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
    @State private var name: String = {
        let f = DateFormatter(); f.dateFormat = "MMM d · h:mm a"; return "Space \(f.string(from: Date()))"
    }()
    @State private var saveError: String?
    @State private var didSave = false
    @State private var savedSessionForViewer: RoomSession?

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.08, blue: 0.14).ignoresSafeArea()

            if let session = savedSessionForViewer {
                // Real scan viewer only — Delete + Done are on this screen
                RoomViewerView(session: session)
                    .environmentObject(store)
                    .onDisappear {
                        model.stop()
                        dismiss()
                    }
            } else {
                switch model.phase {
                case .idle, .scanning, .failed:
                    scanCameraLayer
                case .processing, .saving, .preview:
                    processingLayer
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.exportReadyToken) { _, _ in
            autoSaveAndOpenViewer()
        }
        .onAppear {
            if name.isEmpty { name = defaultName() }
            model.onExportReady = {
                // Must hop to main; bake completion already on main
                autoSaveAndOpenViewer()
            }
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
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            // Status + build stamp (easy to verify)
            if model.phase == .scanning {
                VStack(spacing: 4) {
                    Text(model.simpleStatusTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(BuildStamp.id)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.45), in: Capsule())
            }

            Spacer()

            // Balance X button
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var scanBottomBar: some View {
        VStack(spacing: 14) {
            if case .failed(let msg) = model.phase {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                Button("Try Again") { model.start() }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.blue, in: RoundedRectangle(cornerRadius: 16))
            } else if model.phase == .scanning {
                // One clear instruction — like teaching a first-time user
                Text(model.simpleGuide)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Simple progress — not mesh counts
                VStack(spacing: 6) {
                    ProgressView(value: model.simpleProgress)
                        .tint(model.simpleProgress >= 0.85 ? Color.green : AppTheme.blue)
                        .scaleEffect(y: 1.4)
                    Text(model.simpleProgressLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 8)

                Button {
                    model.finishScanning()
                } label: {
                    Text(model.simpleProgress >= 0.85 ? "Finish" : "Finish")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(model.simpleProgress >= 0.85
                                      ? Color.green.opacity(0.95)
                                      : AppTheme.blue)
                        )
                        .shadow(color: (model.simpleProgress >= 0.85 ? Color.green : AppTheme.blue).opacity(0.4), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }


    private var processingLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.05, blue: 0.14),
                    Color(red: 0.04, green: 0.10, blue: 0.28),
                    Color(red: 0.01, green: 0.03, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.blue.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: -40, y: -120)
            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: 80, y: 160)

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(AppTheme.blue.opacity(0.2), lineWidth: 6)
                        .frame(width: 120, height: 120)
                    Circle()
                        .trim(from: 0, to: max(0.05, model.bakeProgress))
                        .stroke(
                            AngularGradient(
                                colors: [AppTheme.blue, Color.cyan, AppTheme.blueDeep, AppTheme.blue],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.35), value: model.bakeProgress)

                    VStack(spacing: 2) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(Int(model.bakeProgress * 100))%")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                VStack(spacing: 10) {
                    Text("Building Your 3D Space")
                    Text(BuildStamp.label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.7))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(model.bakeStatus)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cyan.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut, value: model.bakeStatus)
                }

                HStack(spacing: 10) {
                    processChip("\(model.meshChunks)", "Surfaces")
                    processChip(model.hasColorFrames ? "Color" : "…", "Paint")
                    processChip(model.coverageLabel, "Cover")
                }
                .padding(.top, 8)

                Text("Mapping real colors onto LiDAR mesh\nAlmost There — this is the magic step.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private func processChip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }


    private func defaultName() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return "Space \(f.string(from: Date()))"
    }

    /// Save mesh to My Rooms and open the real viewer (no black Review screen).
    private func autoSaveAndOpenViewer() {
        guard savedSessionForViewer == nil else { return }
        guard let payload = model.exportPayload else {
            model.phase = .failed("No mesh built. Scan again and cover more surfaces.")
            return
        }
        model.phase = .saving
        model.bakeStatus = "Saving to My Rooms…"
        model.bakeProgress = 0.98

        let nm = name.isEmpty ? defaultName() : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = model.previewImage
        let chunks = model.meshChunks
        let storeRef = store

        DispatchQueue.global(qos: .userInitiated).async {
            let scnURL = payload.directory.appendingPathComponent(payload.fileName)
            if !FileManager.default.fileExists(atPath: scnURL.path), let scene = payload.scene {
                PhotoTexturedMeshBuilder.normalizeForPreview(scene)
                _ = PhotoTexturedMeshBuilder.writeScene(scene, to: payload.directory, name: payload.fileName)
            }
            // Ensure file exists even if empty write failed — write again
            if !FileManager.default.fileExists(atPath: scnURL.path), let scene = payload.scene {
                _ = PhotoTexturedMeshBuilder.writeScene(scene, to: payload.directory, name: payload.fileName)
            }
            do {
                let session = try storeRef.saveFullEnvironment(
                    name: nm,
                    notes: "Full environment LiDAR + photo color",
                    meshFileName: payload.fileName,
                    sourceDirectory: payload.directory,
                    preview: preview,
                    meshChunkCount: chunks
                )
                DispatchQueue.main.async {
                    self.didSave = true
                    self.model.controller.stop()
                    self.model.bakeProgress = 1
                    self.model.bakeStatus = "Opening scan…"
                    self.savedSessionForViewer = session
                }
            } catch {
                DispatchQueue.main.async {
                    self.model.phase = .failed("Save failed: \(error.localizedDescription)")
                }
            }
        }
    }
}


// PreviewMeshView kept for optional debug only

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
        let v = SCNView(frame: UIScreen.main.bounds)
        v.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = true
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 30
        v.isPlaying = true
        v.rendersContinuously = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        context.coordinator.view = v
        context.coordinator.load(scene: scene, url: url)
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if context.coordinator.lastToken != resetToken {
            context.coordinator.lastToken = resetToken
            context.coordinator.load(scene: scene, url: url)
        } else if let scene, uiView.scene !== scene {
            context.coordinator.load(scene: scene, url: nil)
        }
        // Refit when we finally have a real size
        if uiView.bounds.width > 10 {
            context.coordinator.refitIfNeeded()
        }
    }

    final class Coordinator {
        weak var view: SCNView?
        var lastToken: Int = -1
        private var didFit = false

        func load(scene: SCNScene?, url: URL?) {
            didFit = false
            if let scene {
                apply(scene)
                return
            }
            guard let url else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let loaded = try? SCNScene(url: url, options: nil)
                DispatchQueue.main.async {
                    if let loaded { self?.apply(loaded) }
                }
            }
        }

        private func apply(_ scene: SCNScene) {
            // Force visible materials
            scene.background.contents = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
            scene.rootNode.enumerateChildNodes { node, _ in
                guard let mats = node.geometry?.materials else { return }
                for m in mats {
                    m.lightingModel = .constant
                    m.isDoubleSided = true
                    m.fillMode = .fill
                    m.writesToDepthBuffer = true
                    if m.diffuse.contents == nil {
                        m.diffuse.contents = UIColor(red: 0.55, green: 0.6, blue: 0.7, alpha: 1)
                    }
                }
            }
            // Ensure ambient
            if scene.rootNode.childNode(withName: "viewerAmbient", recursively: false) == nil {
                let a = SCNNode()
                a.name = "viewerAmbient"
                a.light = SCNLight()
                a.light?.type = .ambient
                a.light?.intensity = 1600
                scene.rootNode.addChildNode(a)
            }

            PhotoTexturedMeshBuilder.normalizeForPreview(scene)
            view?.scene = scene
            DispatchQueue.main.async { [weak self] in
                self?.refitIfNeeded()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.refitIfNeeded(force: true)
            }
        }

        func refitIfNeeded(force: Bool = false) {
            guard let view, let scene = view.scene else { return }
            if didFit && !force { return }
            guard view.bounds.width > 10 else { return }

            let mesh = scene.rootNode.childNode(withName: "coloredMesh", recursively: true) ?? scene.rootNode
            var minV = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var maxV = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            var found = false

            func visit(_ n: SCNNode) {
                if let g = n.geometry {
                    let (bmin, bmax) = g.boundingBox
                    let corners = [
                        SCNVector3(bmin.x, bmin.y, bmin.z),
                        SCNVector3(bmax.x, bmax.y, bmax.z),
                        SCNVector3(bmin.x, bmax.y, bmin.z),
                        SCNVector3(bmax.x, bmin.y, bmax.z),
                    ]
                    for c in corners {
                        let w = n.convertPosition(c, to: scene.rootNode)
                        minV = simd_min(minV, SIMD3(w.x, w.y, w.z))
                        maxV = simd_max(maxV, SIMD3(w.x, w.y, w.z))
                        found = true
                    }
                }
                for c in n.childNodes { visit(c) }
            }
            visit(mesh)

            let center: SCNVector3
            var radius: Float = 1.2
            if found {
                center = SCNVector3(
                    (minV.x + maxV.x) * 0.5,
                    (minV.y + maxV.y) * 0.5,
                    (minV.z + maxV.z) * 0.5
                )
                radius = max(maxV.x - minV.x, max(maxV.y - minV.y, maxV.z - minV.z)) * 0.5
                radius = max(radius, 0.35)
            } else {
                center = SCNVector3Zero
            }

            // Remove old cameras
            scene.rootNode.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }

            let dist = radius * 2.8
            let cam = SCNNode()
            cam.name = "previewCam"
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 55
            cam.camera?.zNear = 0.01
            cam.camera?.zFar = Double(max(100, radius * 50))
            cam.position = SCNVector3(center.x + dist * 0.6, center.y + dist * 0.45, center.z + dist)
            let constraint = SCNLookAtConstraint(target: mesh)
            constraint.isGimbalLockEnabled = true
            cam.constraints = [constraint]
            scene.rootNode.addChildNode(cam)

            view.pointOfView = cam
            view.defaultCameraController.target = center
            view.defaultCameraController.pointOfView = cam
            didFit = true
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
    @Published var instruction = "Point At Your Space And Walk Slowly"
    @Published var simpleGuide = "Point At Your Space And Walk Slowly"
    @Published var simpleStatusTitle = "Ready"
    @Published var simpleProgress: Double = 0
    @Published var simpleProgressLabel = "Getting Started"
    @Published var statusTitle = "Full 3D Scan"
    @Published var detailLine = "LiDAR + real colors"
    @Published var meshChunks = 0
    @Published var coverageLabel = "—"
    @Published var aiCoachTip = "Move slowly · AI is mapping surfaces"
    @Published var hasColorFrames = false
    @Published var previewImage: UIImage?
    @Published var exportPayload: ExportPayload?
    @Published var previewMeshURL: URL?
    @Published var previewScene: SCNScene?
    @Published var viewResetToken: Int = 0
    @Published var bakeProgress: Double = 0
    @Published var bakeStatus: String = "Preparing…"
    @Published var exportReadyToken: Int = 0
    /// Called on main when bake finishes — opens Rooms viewer (not black Review).
    var onExportReady: (() -> Void)?

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
        instruction = "Point At Your Space And Walk Slowly"
        simpleGuide = "Point At Your Space And Walk Slowly"
        simpleStatusTitle = "Ready"
        simpleProgress = 0
        simpleProgressLabel = "Getting Started"
        controller.onStats = { [weak self] chunks, frames in
            Task { @MainActor in
                guard let self else { return }
                self.meshChunks = chunks
                self.hasColorFrames = frames > 0
                self.applySimpleGuidance(meshCount: chunks)
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

    /// Everyday language only — no mesh counts for the user.
    @MainActor
    private func applySimpleGuidance(meshCount: Int) {
        // meshCount = live ARKit surfaces (normal walking is fine)
        if meshCount < 4 {
            simpleGuide = "Point At Your Space And Walk Around"
            simpleStatusTitle = "Starting…"
            simpleProgress = 0.12
            simpleProgressLabel = "Getting Started"
        } else if meshCount < 12 {
            simpleGuide = "Keep Walking · Cover Everything You See"
            simpleStatusTitle = "Scanning…"
            simpleProgress = 0.35
            simpleProgressLabel = "Keep Going"
        } else if meshCount < 22 {
            simpleGuide = "Walk Every Side · Normal Pace Is Fine"
            simpleStatusTitle = "Scanning…"
            simpleProgress = 0.6
            simpleProgressLabel = "Halfway There"
        } else if meshCount < 35 {
            simpleGuide = "Almost Done · Fill Any Empty Spots"
            simpleStatusTitle = "Looking Good"
            simpleProgress = 0.85
            simpleProgressLabel = "Almost Ready"
        } else {
            simpleGuide = "Looking Great · Tap Finish"
            simpleStatusTitle = "Ready"
            simpleProgress = 1.0
            simpleProgressLabel = "Tap Finish"
        }
        aiCoachTip = ""
        detailLine = ""
        coverageLabel = simpleProgressLabel
    }

    func finishScanning() {
        guard phase == .scanning else { return }
        phase = .processing
        statusTitle = "Processing"
        instruction = "Building Your 3D View…"
        bakeProgress = 0.02
        bakeStatus = "Locking Scan…"
        controller.stopCapturing()
        previewImage = controller.snapshot()

        let ctrl = controller
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async {
                self.bakeProgress = 0.1
                self.bakeStatus = "Pulling Full Space Mesh…"
            }

            // Harvest on background — never sleep on UI thread
            ctrl.forceFinalHarvest()

            DispatchQueue.main.async {
                self.bakeProgress = 0.2
                self.bakeStatus = "Painting Real Colors…"
            }

            PhotoTexturedMeshBuilder.progressHandler = { [weak self] p, msg in
                DispatchQueue.main.async {
                    self?.bakeProgress = min(max(0.2 + p * 0.75, 0.2), 0.99)
                    self?.bakeStatus = msg
                }
            }

            let result = ctrl.buildExportFast()
            PhotoTexturedMeshBuilder.progressHandler = nil

            DispatchQueue.main.async {
                if let result, let scene = result.scene,
                   scene.rootNode.childNode(withName: "coloredMesh", recursively: true) != nil
                    || !scene.rootNode.childNodes.isEmpty {
                    self.exportPayload = result
                    self.previewMeshURL = result.directory.appendingPathComponent(result.fileName)
                    self.previewScene = scene
                    self.bakeProgress = 0.97
                    self.bakeStatus = "Opening Your Scan…"
                    self.phase = .saving
                    self.controller.stop()
                    self.exportReadyToken += 1
                    self.onExportReady?()
                } else {
                    let mc = self.meshChunks
                    self.phase = .failed(
                        mc == 0
                        ? "No Mesh Captured. Walk Around Your Space Until Coverage Looks Full, Then Tap Finish."
                        : "Could Not Build The 3D View. Try Walking All Sides Once More."
                    )
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
    private let captureQueue = DispatchQueue(label: "enviromap.scan.capture", qos: .userInitiated)
    /// Copied geometry only — never keep live ARMeshAnchor refs long-term
    private var chunks: [UUID: CapturedMeshChunk] = [:]
    private var keyframes: [PhotoTexturedMeshBuilder.Keyframe] = []
    private var lastKeyframeTime: TimeInterval = 0
    private var lastMeshCopyTime: TimeInterval = 0
    private var lastCamPos: SIMD3<Float>?
    private var lastStatsEmit: TimeInterval = 0
    private var maxKeyframes: Int { MeshDensityConfig.maxKeyframes }
    private var maxChunks: Int { MeshDensityConfig.maxChunks }
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
        // Live ARKit mesh shows as blue coverage (styled in renderer)
        scn.debugOptions = []
        scn.rendersContinuously = true
        view.addSubview(scn)
        arView = scn
        let root = SCNNode()
        root.name = "coverageRoot"
        scn.scene.rootNode.addChildNode(root)
        coverageRoot = root
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        stateLock.lock()
        // Emergency trim — keep newest half of keyframes + chunks
        if keyframes.count > 10 {
            keyframes = Array(keyframes.suffix(10))
        }
        if chunks.count > 280 {
            let ranked = chunks.values.sorted { $0.positions.count > $1.positions.count }
            var keep: [UUID: CapturedMeshChunk] = [:]
            for c in ranked.prefix(280) { keep[c.id] = c }
            chunks = keep
        }
        stateLock.unlock()
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
        classCounts.removeAll()
        latestAITip = "AI ready · point at your space"
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.coverageRoot?.childNodes.forEach { $0.removeFromParentNode() }
        }

        let config = ARWorldTrackingConfiguration()
        // Dense LiDAR mesh of everything (not RoomPlan walls-only)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else {
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .automatic
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        // Smoother tracking → better mesh continuity

        isRunning = true
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopCapturing() {
        // Stop live keyframes only — harvest runs once on background queue
        isRunning = false
    }

    func stop() {
        isRunning = false
        arView?.session.pause()
    }

    func snapshot() -> UIImage? { arView?.snapshot() }

    func forceFinalHarvest() {
        // THE only geometry pull — full quality from ARKit after the walk
        guard let session = arView?.session else { return }

        // Brief settle so ARKit can densify last surfaces
        Thread.sleep(forTimeInterval: 0.15)

        func pull(from frame: ARFrame) -> [UUID: CapturedMeshChunk] {
            var fresh: [UUID: CapturedMeshChunk] = [:]
            let meshes = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            for mesh in meshes {
                if let chunk = Self.copyChunk(from: mesh, fullQuality: true) {
                    fresh[chunk.id] = chunk
                }
            }
            if fresh.isEmpty {
                for mesh in meshes {
                    if let chunk = Self.copyChunk(from: mesh, fullQuality: false) {
                        fresh[chunk.id] = chunk
                    }
                }
            }
            return fresh
        }

        autoreleasepool {
            if let frame = session.currentFrame {
                ingestKeyframe(from: frame)
                var all = pull(from: frame)

                // Second pass — ARKit often densifies mid-harvest
                Thread.sleep(forTimeInterval: 0.12)
                if let frame2 = session.currentFrame {
                    ingestKeyframe(from: frame2)
                    let second = pull(from: frame2)
                    for (id, chunk) in second {
                        if let old = all[id], old.positions.count >= chunk.positions.count {
                            continue
                        }
                        all[id] = chunk
                    }
                }

                stateLock.lock()
                chunks = all
                let total = chunks.count
                let verts = chunks.values.reduce(0) { $0 + $1.positions.count }
                stateLock.unlock()
                print("[EnviroMap] HARVEST chunks=\(total) verts=\(verts)")
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
        PhotoTexturedMeshBuilder.normalizeForPreview(scene)
        _ = PhotoTexturedMeshBuilder.writeScene(scene, to: tmp, name: "room_full.scn")
        return .init(directory: tmp, fileName: "room_full.scn", scene: scene)
    }

    /// Full export with texture files + scn (background after Review appears).
    func persistExportInBackground(_ payload: FullEnvironmentScanModel.ExportPayload) {
        // Scene already written in buildExportFast — never re-bake (was causing freezes).
        let scn = payload.directory.appendingPathComponent(payload.fileName)
        if FileManager.default.fileExists(atPath: scn.path) { return }
        guard let scene = payload.scene else { return }
        DispatchQueue.global(qos: .utility).async {
            _ = PhotoTexturedMeshBuilder.writeScene(scene, to: payload.directory, name: payload.fileName)
        }
    }

    // MARK: - Live blue mesh (throttled — better coverage feedback)

    private var lastVizTime: [UUID: TimeInterval] = [:]
    private var lastClassNoteTime: TimeInterval = 0

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARMeshAnchor else { return nil }
        return SCNNode()
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        if showBlueMesh {
            stateLock.lock()
            let chunkCount = chunks.count
            stateLock.unlock()
            if chunkCount <= 30 {
                applyBlueWire(node: node, mesh: mesh)
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Never rebuild wire on updates — that was the freeze.
        // Classification only, rarely.
        guard let mesh = anchor as? ARMeshAnchor else { return }
        noteClassification(from: mesh)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        lastVizTime.removeValue(forKey: anchor.identifier)
        stateLock.lock()
        chunks.removeValue(forKey: anchor.identifier)
        stateLock.unlock()
    }

    private func applyBlueWire(node: SCNNode, mesh: ARMeshAnchor) {
        // Smooth blue mapping mesh (3D Snap style) — subsampled lines only
        guard showBlueMesh else {
            node.geometry = nil
            return
        }
        guard let geom = Self.wireGeometry(mesh.geometry) else { return }
        node.geometry = geom
    }

    /// Read AI prefs each session
    private var showBlueMesh: Bool {
        // Default OFF — blue wire was a major freeze source. Settings can re-enable.
        UserDefaults.standard.object(forKey: "enviromap.scan.showBlueMesh") as? Bool ?? false
    }
    private var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }
    private var aiCoachEnabled: Bool {
        let improve = UserDefaults.standard.object(forKey: "enviromap.ai.improveTools") as? Bool ?? true
        let coach = UserDefaults.standard.object(forKey: "enviromap.scan.aiCoach") as? Bool ?? true
        return improve && coach
    }

    private(set) var latestAITip: String = "Move slowly · cover everything you want in 3D"
    private var classCounts: [String: Int] = [:]


    private static func wireGeometry(_ mesh: ARMeshGeometry) -> SCNGeometry? {
        let vCount = mesh.vertices.count
        guard vCount > 0, mesh.faces.count > 0, vCount < 40_000 else { return nil }
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
        // Subsample triangles for smooth 60fps blue mesh
        let faceStep = MeshDensityConfig.blueWireFaceStep(faceCount: faces.count)
        for f in stride(from: 0, to: faces.count, by: faceStep) {
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
        let ts = frame.timestamp

        // FIRST PRINCIPLES: do NOT copy mesh geometry while walking.
        // Live mesh copies steal CPU from ARKit → sparse holes when you walk normal speed.
        // ARKit builds the dense mesh; we harvest everything once on Finish.

        let liveMeshCount = frame.anchors.compactMap { $0 as? ARMeshAnchor }.count

        let pos = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )
        var moving = false
        if let prev = lastCamPos {
            moving = simd_length(pos - prev) > 0.01
        }
        lastCamPos = pos

        // Color frames only — cheap, lets you walk at normal pace
        let kfI = MeshDensityConfig.keyframeInterval(movingFast: moving)
        if ts - lastKeyframeTime >= kfI {
            lastKeyframeTime = ts
            autoreleasepool { ingestKeyframe(from: frame) }
        }

        // Progress from ARKit's live mesh count (not our stored copies)
        if ts - lastStatsEmit >= 0.35 {
            stateLock.lock()
            let fn = keyframes.count
            stateLock.unlock()
            emitStats(meshCount: max(liveMeshCount, 1), frameCount: fn)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error.localizedDescription)
        }
    }

    // Live blue mesh = free ARKit coverage view (no geometry copy cost)
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARMeshAnchor else { return }
        styleCoverageNode(node)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARMeshAnchor else { return }
        styleCoverageNode(node)
    }

    private func styleCoverageNode(_ node: SCNNode) {
        let paint: (SCNNode) -> Void = { n in
            guard let g = n.geometry else { return }
            for m in g.materials {
                m.diffuse.contents = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.4)
                m.transparency = 0.4
                m.isDoubleSided = true
                m.lightingModel = .constant
                m.writesToDepthBuffer = true
            }
        }
        paint(node)
        node.enumerateChildNodes { child, _ in paint(child) }
    }

    private func ingestMeshes(from frame: ARFrame) {
        ingestMeshAnchors(frame.anchors.compactMap { $0 as? ARMeshAnchor })
    }

    private func ingestMeshAnchors(_ anchors: [ARMeshAnchor]) {
        guard !anchors.isEmpty else { return }
        var copied: [CapturedMeshChunk] = []
        copied.reserveCapacity(anchors.count)
        for mesh in anchors {
            if let chunk = Self.copyChunk(from: mesh, fullQuality: false) {
                copied.append(chunk)
            }
        }
        guard !copied.isEmpty else { return }

        stateLock.lock()
        for c in copied {
            chunks[c.id] = c
        }
        if chunks.count > maxChunks {
            let ranked = chunks.values.sorted { $0.positions.count > $1.positions.count }
            let removeCount = chunks.count - maxChunks
            for i in 0..<removeCount {
                chunks.removeValue(forKey: ranked[i].id)
            }
        }
        let meshCount = chunks.count
        let frameCount = keyframes.count
        stateLock.unlock()

        updateAICoach(meshCount: meshCount)
        emitStats(meshCount: meshCount, frameCount: frameCount)
        // Coverage markers only occasionally (main-ish SCN work)
        // No coverage SCN markers — smoothness first

    }

    private func updateAICoach(meshCount: Int) {
        // Guidance is applied on the model from mesh count (simple consumer copy).
        latestAITip = ""
    }

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
        // Skip if already at cap — avoid peak memory during long scans
        stateLock.lock()
        let atCap = keyframes.count >= maxKeyframes
        stateLock.unlock()
        if atCap {
            // Replace oldest instead of growing
            stateLock.lock()
            if !keyframes.isEmpty { keyframes.removeFirst() }
            stateLock.unlock()
        }

        let orientation: UIInterfaceOrientation = .portrait
        let viewport = arView?.bounds.size ?? CGSize(width: 390, height: 844)
        // Always live-size (never 960 mid-scan)
        let width = MeshDensityConfig.keyframeMaxWidth
        guard let kf = PhotoTexturedMeshBuilder.makeKeyframe(
            from: frame,
            orientation: orientation,
            viewport: viewport,
            maxWidth: width
        ) else { return }

        stateLock.lock()
        keyframes.append(kf)
        if keyframes.count > maxKeyframes {
            keyframes.removeFirst(keyframes.count - maxKeyframes)
        }
        stateLock.unlock()
        // Progress comes from session(didUpdate) live ARKit mesh count — not empty chunks
    }

    private func emitStats(meshCount: Int, frameCount: Int) {
        let now = CACurrentMediaTime()
        if now - lastStatsEmit < 0.6 { return }
        lastStatsEmit = now
        DispatchQueue.main.async { [weak self] in
            self?.onStats?(meshCount, frameCount)
        }
    }

    /// Deep-copy mesh buffers while the anchor is valid (during this callback only).

    private func noteClassification(from mesh: ARMeshAnchor) {
        guard aiCoachEnabled else { return }
        let now = CACurrentMediaTime()
        if now - lastClassNoteTime < 1.5 { return }
        lastClassNoteTime = now
        // ARMeshClassification via geometry if available (iOS 14+)
        let g = mesh.geometry
        // faces with classification - optional path
        // Use bounding box heuristic as AI assist fallback
        let t = mesh.transform
        let y = t.columns.3.y
        if y < 0.35 {
            classCounts["floor", default: 0] += 1
        } else if y > 1.8 {
            classCounts["ceiling", default: 0] += 1
        } else {
            classCounts["wall", default: 0] += 1
        }
        _ = g
    }

    private static func copyChunk(from anchor: ARMeshAnchor, fullQuality: Bool = false) -> CapturedMeshChunk? {
        let geom = anchor.geometry
        let vSource = geom.vertices
        let nSource = geom.normals
        let faces = geom.faces
        let vCount = vSource.count
        guard vCount > 0, faces.count > 0 else { return nil }

        // CRITICAL: never drop a whole anchor (that deleted cars/walls).
        // Only subsample when huge. Done harvest uses step 1 unless insane.
        let step: Int
        if fullQuality {
            step = 1  // never thin on Finish — holes are worse than big files
        } else {
            step = MeshDensityConfig.liveVertexStep(vCount: vCount)
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(vCount / max(step, 1) + 1)
        normals.reserveCapacity(vCount / max(step, 1) + 1)
        var remap = [Int: Int]()
        remap.reserveCapacity(vCount / max(step, 1) + 1)

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
        let faceStep = fullQuality ? 1 : MeshDensityConfig.liveFaceStep(faceCount: faces.count)
        indices.reserveCapacity(max(1, faces.count / faceStep) * faces.indexCountPerPrimitive)
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
