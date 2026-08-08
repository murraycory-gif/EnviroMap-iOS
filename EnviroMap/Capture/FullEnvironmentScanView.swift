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
        .preferredColorScheme(.dark)
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
                    .disabled(model.meshChunks < 3)

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

    // MARK: - Preview before save (app design language)

    private var previewLayer: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    model.rescan()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Rescan")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                }
                Spacer()
                Text("Review Scan")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 70)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // 3D preview
            ZStack {
                if let url = model.previewMeshURL {
                    PreviewMeshView(url: url)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 12)
                } else {
                    ProgressView().tint(.white)
                }

                VStack {
                    Spacer()
                    HStack {
                        Label("Drag · Pinch To Inspect", systemImage: "hand.draw")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        Text("Full Color Mesh")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(20)
                }
            }
            .frame(maxHeight: .infinity)

            // Save card (matches EnviroMap light-card language on dark)
            VStack(alignment: .leading, spacing: 14) {
                Text("Looks Good?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("Review the full-color mesh. Rescan if holes are too big, or save to My Rooms.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    TextField("Room Name", text: $name)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                        .foregroundStyle(.white)
                }

                HStack(spacing: 12) {
                    Button {
                        model.rescan()
                    } label: {
                        Text("Rescan")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                            )
                            .foregroundStyle(.white)
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.blue, AppTheme.blueDeep],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(didSave || model.phase == .saving)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.14, blue: 0.22))
                    .shadow(color: .black.opacity(0.35), radius: 20, y: -4)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
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

// MARK: - Lightweight preview SCNView

struct PreviewMeshView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        DispatchQueue.global(qos: .userInitiated).async {
            if let scene = try? SCNScene(url: url, options: [
                .createNormalsIfAbsent: true,
                .checkConsistency: true,
            ]) {
                // Ensure photo vertex colors render
                scene.rootNode.enumerateChildNodes { node, _ in
                    guard let mats = node.geometry?.materials else { return }
                    for mat in mats {
                        mat.lightingModel = .constant
                        mat.isDoubleSided = true
                        mat.shaderModifiers = [
                            .surface: """
                            #pragma body
                            _surface.diffuse = float4(_geometry.color.rgb, 1.0);
                            _surface.emission = float4(_geometry.color.rgb * 0.08, 1.0);
                            """
                        ]
                    }
                }
                let amb = SCNNode()
                amb.light = SCNLight()
                amb.light?.type = .ambient
                amb.light?.intensity = 1000
                scene.rootNode.addChildNode(amb)

                DispatchQueue.main.async {
                    v.scene = scene
                    v.defaultCameraController.automaticTarget = true
                    v.defaultCameraController.inertiaEnabled = true
                }
            }
        }
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Model

@MainActor
final class FullEnvironmentScanModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case processing
        case preview
        case saving
        case failed(String)
    }

    struct ExportPayload {
        let directory: URL
        let fileName: String
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

    let controller = FullEnvScanController()

    func start() {
        exportPayload = nil
        previewMeshURL = nil
        meshChunks = 0
        hasColorFrames = false
        coverageLabel = "—"
        phase = .scanning
        statusTitle = "Scanning"
        instruction = "Point at everything — furniture, floor, walls, objects. Blue mesh = captured."
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

    func stop() {
        controller.stop()
    }

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
        previewImage = controller.snapshot()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.controller.buildExport()
            DispatchQueue.main.async {
                if let result {
                    self.exportPayload = result
                    self.previewMeshURL = result.directory.appendingPathComponent(result.fileName)
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

    func makeUIViewController(context: Context) -> FullEnvScanController {
        model.controller
    }

    func updateUIViewController(_ uiViewController: FullEnvScanController, context: Context) {}
}

// MARK: - ARKit controller

final class FullEnvScanController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    private var arView: ARSCNView!
    private var isRunning = false

    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var keyframes: [PhotoTexturedMeshBuilder.Keyframe] = []
    private var lastKeyframeTime: TimeInterval = 0
    private let maxKeyframes = 72

    var onStats: ((Int, Int) -> Void)?
    var onError: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let scn = ARSCNView(frame: view.bounds)
        scn.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scn.delegate = self
        scn.session.delegate = self
        scn.automaticallyUpdatesLighting = true
        scn.scene = SCNScene()
        view.addSubview(scn)
        arView = scn
    }

    func start() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
                || ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            onError?("This device cannot build a LiDAR mesh.")
            return
        }

        meshAnchors.removeAll()
        keyframes.removeAll()
        lastKeyframeTime = 0

        let config = ARWorldTrackingConfiguration()
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

        isRunning = true
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopCapturing() {
        isRunning = false
    }

    func stop() {
        isRunning = false
        arView?.session.pause()
    }

    func snapshot() -> UIImage? {
        arView?.snapshot()
    }

    func buildExport() -> FullEnvironmentScanModel.ExportPayload? {
        // Snapshot anchors now (deep copy geometry lives on anchors)
        let anchors = Array(meshAnchors.values)
        let frames = keyframes
        guard !anchors.isEmpty else { return nil }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnviroMapFull_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        guard let fileName = PhotoTexturedMeshBuilder.export(
            anchors: anchors,
            keyframes: frames,
            to: tmp
        ) else { return nil }

        return .init(directory: tmp, fileName: fileName)
    }

    // MARK: Mesh viz

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARMeshAnchor else { return nil }
        return SCNNode()
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        meshAnchors[mesh.identifier] = mesh
        updateViz(node: node, mesh: mesh)
        emitStats()
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        meshAnchors[mesh.identifier] = mesh
        updateViz(node: node, mesh: mesh)
        emitStats()
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        meshAnchors.removeValue(forKey: anchor.identifier)
        emitStats()
    }

    private func updateViz(node: SCNNode, mesh: ARMeshAnchor) {
        guard let geom = Self.quickGeometry(mesh.geometry) else { return }
        node.geometry = geom
    }

    private static func quickGeometry(_ mesh: ARMeshGeometry) -> SCNGeometry? {
        let vCount = mesh.vertices.count
        guard vCount > 0, mesh.faces.count > 0 else { return nil }

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
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        var indices = [UInt32]()
        let faces = mesh.faces
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
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: faces.count, bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geom = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.fillMode = .lines
        mat.diffuse.contents = UIColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 0.9)
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        geom.materials = [mat]
        return geom
    }

    // MARK: Color keyframes

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning else { return }
        let t = frame.timestamp
        if t - lastKeyframeTime < 0.22 { return } // ~4–5 fps keyframes
        lastKeyframeTime = t

        guard let copied = Self.copyPixelBuffer(frame.capturedImage) else { return }

        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait

        let viewport = arView?.bounds.size ?? CGSize(width: 390, height: 844)
        let display = frame.displayTransform(for: orientation, viewportSize: viewport)

        let kf = PhotoTexturedMeshBuilder.Keyframe(
            camera: frame.camera,
            image: copied,
            orientation: orientation,
            viewport: viewport,
            displayTransform: display,
            capturedAt: t
        )
        keyframes.append(kf)
        if keyframes.count > maxKeyframes {
            keyframes.removeFirst(keyframes.count - maxKeyframes)
        }
        emitStats()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onError?(error.localizedDescription)
    }

    private func emitStats() {
        onStats?(meshAnchors.count, keyframes.count)
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
