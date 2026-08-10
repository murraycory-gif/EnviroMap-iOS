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
            case .idle, .scanning, .failed:
                scanCameraLayer
            case .processing:
                processingLayer
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

            // Live capture status + AI coach
            if model.phase == .scanning {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                        Text(model.meshChunks > 0
                             ? "Mapping… \(model.meshChunks) surfaces"
                             : "Point at a surface to start")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("BLUE = mapped")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 1))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.45), in: Capsule())

                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color(red: 0.5, green: 0.8, blue: 1))
                        Text(model.aiCoachTip)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.1, green: 0.25, blue: 0.45).opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
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


    // MARK: - Edgy processing / loading screen

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
                    Text("Building Your World")
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

                Text("Mapping real colors onto LiDAR mesh\nHang tight — this is the magic step.")
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

    // MARK: - Preview before save (light AppTheme design)

    private var previewLayer: some View {
        ZStack {
            // Full-screen 3D is the product — not a tiny card
            Color.black.ignoresSafeArea()

            if let scene = model.previewScene {
                PreviewMeshView(scene: scene, resetToken: model.viewResetToken)
                    .ignoresSafeArea()
            } else if let url = model.previewMeshURL {
                PreviewMeshView(url: url, resetToken: model.viewResetToken)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Top chrome
            VStack(spacing: 0) {
                HStack {
                    // Delete / discard
                    Button {
                        model.rescan()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.red.opacity(0.85), in: Circle())
                    }
                    .accessibilityLabel("Delete Scan")

                    Spacer()

                    Text("Your Scan")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    // Save
                    Button {
                        save()
                    } label: {
                        Group {
                            if model.phase == .saving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.blue, AppTheme.blueDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                    }
                    .disabled(didSave || model.phase == .saving)
                    .accessibilityLabel("Save Scan")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Bottom sheet: name + actions
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Drag To Spin · Pinch To Zoom", systemImage: "hand.draw.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text("Full Color")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white, in: Capsule())
                    }

                    Text("Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("Space name", text: $name)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)

                    HStack(spacing: 10) {
                        Button {
                            model.rescan()
                        } label: {
                            Text("Rescan")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
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
                        .fill(Color.black.opacity(0.72))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Could Not Save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func save() {
        guard let payload = model.exportPayload else {
            saveError = "No mesh to save. Scan again."
            return
        }
        model.phase = .saving
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = model.previewImage
        let chunks = model.meshChunks
        let storeRef = store
        let ctrl = model.controller

        DispatchQueue.global(qos: .userInitiated).async {
            let scnURL = payload.directory.appendingPathComponent(payload.fileName)
            if !FileManager.default.fileExists(atPath: scnURL.path), let scene = payload.scene {
                PhotoTexturedMeshBuilder.normalizeForPreview(scene)
                _ = PhotoTexturedMeshBuilder.writeScene(scene, to: payload.directory, name: payload.fileName)
            }
            do {
                _ = try storeRef.saveFullEnvironment(
                    name: nm,
                    notes: "Full environment LiDAR + photo color",
                    meshFileName: payload.fileName,
                    sourceDirectory: payload.directory,
                    preview: preview,
                    meshChunkCount: chunks
                )
                DispatchQueue.main.async {
                    self.didSave = true
                    ctrl.stop()
                    self.dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    self.model.phase = .preview
                    self.saveError = error.localizedDescription
                }
            }
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
        let v = SCNView(frame: .zero)
        v.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = true
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.isPlaying = true
        v.rendersContinuously = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.defaultCameraController.maximumVerticalAngle = 89
        v.defaultCameraController.minimumVerticalAngle = -89
        context.coordinator.scnView = v

        if let scene {
            Self.prepare(scene)
            v.scene = scene
            // Fit after layout so bounds are valid
            DispatchQueue.main.async {
                context.coordinator.fitCamera(in: v, scene: scene)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                context.coordinator.fitCamera(in: v, scene: scene)
            }
        } else if let url {
            DispatchQueue.global(qos: .userInitiated).async {
                if let scene = try? SCNScene(url: url, options: nil) {
                    Self.prepare(scene)
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
        // Assign scene if it arrived after view created
        if let scene, uiView.scene !== scene {
            Self.prepare(scene)
            uiView.scene = scene
            context.coordinator.fitCamera(in: uiView, scene: scene)
        }
        if context.coordinator.lastReset != resetToken {
            context.coordinator.lastReset = resetToken
            if let scene = uiView.scene {
                context.coordinator.fitCamera(in: uiView, scene: scene)
            }
        }
    }

    static func prepare(_ scene: SCNScene) {
        scene.background.contents = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geos = node.geometry else { return }
            for mat in geos.materials {
                mat.lightingModel = .constant
                mat.isDoubleSided = true
                mat.writesToDepthBuffer = true
                mat.readsFromDepthBuffer = true
                mat.fillMode = .fill
                mat.shaderModifiers = [:]
                // Ensure diffuse is never nil
                if mat.diffuse.contents == nil {
                    mat.diffuse.contents = UIColor(white: 0.7, alpha: 1)
                }
            }
            // Force solid fill
            if geos.firstMaterial != nil {
                geos.firstMaterial?.fillMode = .fill
            }
        }
        // Ambient so constant materials stay bright
        if scene.rootNode.childNode(withName: "viewerAmbient", recursively: false) == nil {
            let amb = SCNNode()
            amb.name = "viewerAmbient"
            amb.light = SCNLight()
            amb.light?.type = .ambient
            amb.light?.intensity = 1200
            amb.light?.color = UIColor.white
            scene.rootNode.addChildNode(amb)
        }
    }

    final class Coordinator {
        var scnView: SCNView?
        var lastReset: Int = -1

        func fitCamera(in view: SCNView, scene: SCNScene) {
            PhotoTexturedMeshBuilder.normalizeForPreview(scene)

            if let cam = scene.rootNode.childNode(withName: "previewCam", recursively: true) {
                view.pointOfView = cam
                view.defaultCameraController.pointOfView = cam
                view.defaultCameraController.target = SCNVector3Zero
            }
            view.allowsCameraControl = true
            view.autoenablesDefaultLighting = true
            view.isPlaying = true
            view.rendersContinuously = true
            // Force redraw after layout
            view.setNeedsDisplay()
            view.layoutIfNeeded()
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
    @Published var aiCoachTip = "Move slowly · AI is mapping surfaces"
    @Published var hasColorFrames = false
    @Published var previewImage: UIImage?
    @Published var exportPayload: ExportPayload?
    @Published var previewMeshURL: URL?
    @Published var previewScene: SCNScene?
    @Published var viewResetToken: Int = 0
    @Published var bakeProgress: Double = 0
    @Published var bakeStatus: String = "Preparing…"

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
        instruction = "Walk around every object · blue mesh must cover cars & furniture fully"
        controller.onStats = { [weak self] chunks, frames in
            Task { @MainActor in
                self?.meshChunks = chunks
                self?.hasColorFrames = frames > 0
                self?.coverageLabel = chunks > 80 ? "Great" : chunks > 35 ? "Good" : chunks > 12 ? "OK" : "Low"
                if let tip = self?.controller.latestAITip, !tip.isEmpty {
                    self?.aiCoachTip = tip
                }
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
        bakeProgress = 0.02
        bakeStatus = "Locking scan data…"
        controller.stopCapturing()
        previewImage = controller.snapshot()
        controller.forceFinalHarvest()
        bakeProgress = 0.08
        bakeStatus = "Preparing color bake…"

        let ctrl = controller
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            PhotoTexturedMeshBuilder.progressHandler = { [weak self] p, msg in
                DispatchQueue.main.async {
                    self?.bakeProgress = min(max(p, 0.08), 0.99)
                    self?.bakeStatus = msg
                }
            }

            let result = ctrl.buildExportFast()
            PhotoTexturedMeshBuilder.progressHandler = nil

            DispatchQueue.main.async {
                if let result, let scene = result.scene, !scene.rootNode.childNodes.isEmpty {
                    self.exportPayload = result
                    self.previewMeshURL = result.directory.appendingPathComponent(result.fileName)
                    self.previewScene = scene
                    self.viewResetToken += 1
                    self.bakeProgress = 1
                    self.bakeStatus = "Ready"
                    self.phase = .preview
                    self.statusTitle = "Review"
                    self.instruction = "Drag to spin · Pinch to zoom"
                    self.controller.stop()
                    self.controller.persistExportInBackground(result)
                } else {
                    // Never silent-fail: show actionable error
                    let mc = self.meshChunks
                    let fc = self.hasColorFrames
                    self.phase = .failed(
                        mc == 0
                        ? "No mesh captured. Move closer and scan until blue lines cover objects."
                        : "Could not build the 3D view (\(mc) mesh pieces). Try a slower circle around the object."
                    )
                    _ = fc
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
        let blueOn = UserDefaults.standard.object(forKey: "enviromap.scan.showBlueMesh") as? Bool ?? true
        scn.debugOptions = blueOn ? [] : [.showFeaturePoints]
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
        classCounts.removeAll()
        latestAITip = "AI ready · point at your space"
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
        // Full-quality pull right before bake (main/caller may be background)
        if let frame = arView?.session.currentFrame {
            autoreleasepool {
                ingestKeyframe(from: frame)
                let meshes = frame.anchors.compactMap { $0 as? ARMeshAnchor }
                for mesh in meshes {
                    if let chunk = Self.copyChunk(from: mesh, fullQuality: true) {
                        stateLock.lock()
                        chunks[chunk.id] = chunk
                        stateLock.unlock()
                    }
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
        // Visual only — mesh storage happens on captureQueue
        applyBlueWire(node: node, mesh: mesh)
        noteClassification(from: mesh)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        let now = CACurrentMediaTime()
        // Blue wire is expensive — update rarely
        if let last = lastVizTime[mesh.identifier], now - last < 0.75 { return }
        lastVizTime[mesh.identifier] = now
        applyBlueWire(node: node, mesh: mesh)
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
        UserDefaults.standard.object(forKey: "enviromap.scan.showBlueMesh") as? Bool ?? true
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
        let t = frame.timestamp

        // ARMeshAnchor buffers are only valid in this callback — copy here, not async.
        // Intervals are deliberately slower so the UI never freezes mid-scan.
        if t - lastMeshCopyTime >= MeshDensityConfig.meshCopyInterval {
            lastMeshCopyTime = t
            autoreleasepool {
                ingestMeshes(from: frame)
            }
        }

        if t - lastKeyframeTime >= MeshDensityConfig.keyframeInterval {
            lastKeyframeTime = t
            autoreleasepool {
                ingestKeyframe(from: frame)
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error.localizedDescription)
        }
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
        if meshCount % 4 == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.updateCoverageMarkersIfNeeded()
            }
        }
    }

    private func updateAICoach(meshCount: Int) {
        guard aiCoachEnabled else {
            latestAITip = "Walk slowly · blue lines show mapped surfaces"
            return
        }
        // AI tips based on coverage progress + classification mix
        if meshCount < 5 {
            latestAITip = "AI: Point at large surfaces first — floor and walls"
        } else if meshCount < 20 {
            latestAITip = "AI: Walk around objects (cars, sofas) · blue must cover all sides"
        } else if meshCount < 45 {
            latestAITip = "AI: Check gaps — dark corners and under objects"
        } else if classCounts["floor", default: 0] < 3 {
            latestAITip = "AI: Sweep the floor under tables and chairs"
        } else if classCounts["wall", default: 0] < 3 {
            latestAITip = "AI: Scan walls top-to-bottom for full room shape"
        } else {
            latestAITip = "AI: Coverage looking strong · keep filling holes"
        }
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
            maxWidth: MeshDensityConfig.keyframeMaxWidth
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
        if now - lastStatsEmit < 0.45 { return }
        lastStatsEmit = now
        DispatchQueue.main.async { [weak self] in
            self?.onStats?(meshCount, frameCount)
        }
    }

    /// Deep-copy mesh buffers while the anchor is valid (during this callback only).

    private func noteClassification(from mesh: ARMeshAnchor) {
        guard aiCoachEnabled else { return }
        let now = CACurrentMediaTime()
        if now - lastClassNoteTime < 0.8 { return }
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
        // Allow larger anchors so cars/furniture stay complete
        guard vCount < (fullQuality ? MeshDensityConfig.finalVertexSoftCap : MeshDensityConfig.liveVertexSoftCap) else { return nil }

        // Live scan may lightly subsample; final harvest keeps full density.
        let step: Int
        if fullQuality {
            step = 1
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
