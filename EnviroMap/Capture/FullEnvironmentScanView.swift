import SwiftUI
import ARKit
import SceneKit
import UIKit
import AVFoundation

/// Full-environment LiDAR scan with **real camera colors** baked on the mesh
/// (like consumer 3D scan apps — not RoomPlan wall-only models).
struct FullEnvironmentScanView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = FullEnvironmentScanModel()
    @State private var name: String = ""
    @State private var showSave = false
    @State private var saveError: String?
    @State private var didSave = false

    var body: some View {
        ZStack {
            FullEnvARContainer(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.start()
            if name.isEmpty {
                name = defaultName()
            }
        }
        .onDisappear { model.stop() }
        .sheet(isPresented: $showSave) { saveSheet }
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .readyToSave {
                showSave = true
            }
        }
    }

    private var topBar: some View {
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
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Text(model.instruction)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

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
                        Label("Done Scanning", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.blue)

                case .processing:
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Baking Real Colors Onto Mesh…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)

                case .failed(let msg):
                    VStack(spacing: 10) {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { model.start() }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.blue)
                    }

                case .readyToSave, .idle:
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Room Name", text: $name)
                }
                Section {
                    Text("Saves a full 3D mesh with real surface colors from the camera — not just walls.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Save Full Scan") { save() }
                        .font(.headline)
                        .disabled(didSave || model.exportPayload == nil)
                }
            }
            .navigationTitle("Save Full 3D Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSave = false
                        model.start()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private func save() {
        guard let payload = model.exportPayload else {
            saveError = "No mesh to save. Scan longer and try again."
            return
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
            showSave = false
            model.stop()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func defaultName() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return "Space \(f.string(from: Date()))"
    }
}

// MARK: - Model

@MainActor
final class FullEnvironmentScanModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case processing
        case readyToSave
        case failed(String)
    }

    struct ExportPayload {
        let directory: URL
        let fileName: String
    }

    @Published var phase: Phase = .idle
    @Published var instruction = "Move slowly. Point at everything you want in 3D."
    @Published var statusTitle = "Full 3D Scan"
    @Published var detailLine = "Everything · photo colors"
    @Published var meshChunks = 0
    @Published var coverageLabel = "—"
    @Published var hasColorFrames = false
    @Published var previewImage: UIImage?
    @Published var exportPayload: ExportPayload?

    let controller = FullEnvScanController()

    func start() {
        exportPayload = nil
        meshChunks = 0
        hasColorFrames = false
        coverageLabel = "—"
        phase = .scanning
        statusTitle = "Scanning"
        instruction = "Point at EVERYTHING — walls, floor, furniture, objects. Blue mesh = captured."
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
                    self.phase = .readyToSave
                    self.statusTitle = "Ready"
                    self.instruction = "Full-color mesh ready — save it."
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
    private let maxKeyframes = 48

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
        // Show camera feed
        scn.debugOptions = []
        view.addSubview(scn)
        arView = scn
    }

    func start() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
                || ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
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
        // Keep session alive briefly so final anchors stay; don't pause yet
    }

    func stop() {
        isRunning = false
        arView?.session.pause()
    }

    func snapshot() -> UIImage? {
        arView?.snapshot()
    }

    func buildExport() -> FullEnvironmentScanModel.ExportPayload? {
        let anchors = Array(meshAnchors.values)
        guard !anchors.isEmpty else { return nil }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnviroMapFull_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        guard let fileName = PhotoTexturedMeshBuilder.export(
            anchors: anchors,
            keyframes: keyframes,
            to: tmp
        ) else { return nil }

        return .init(directory: tmp, fileName: fileName)
    }

    // MARK: ARSCNViewDelegate — visualize mesh live

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARMeshAnchor else { return nil }
        // Empty node; geometry updated in didUpdate
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
        // Live translucent mesh so user sees coverage while scanning
        guard let geom = Self.quickGeometry(mesh.geometry) else { return }
        node.geometry = geom
        node.simdTransform = matrix_identity_float4x4 // ARSCNView applies anchor transform
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
        mat.diffuse.contents = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 0.85)
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        geom.materials = [mat]
        return geom
    }

    // MARK: ARSessionDelegate — keyframes for color

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning else { return }
        let t = frame.timestamp
        // ~3 keyframes/sec max
        if t - lastKeyframeTime < 0.33 { return }
        lastKeyframeTime = t

        // Copy pixel buffer (ARFrame buffer is reused)
        guard let copied = Self.copyPixelBuffer(frame.capturedImage) else { return }

        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait

        let viewport = arView?.bounds.size ?? CGSize(width: 390, height: 844)

        let kf = PhotoTexturedMeshBuilder.Keyframe(
            camera: frame.camera,
            image: copied,
            orientation: orientation,
            viewport: viewport,
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
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, format,
            attrs as CFDictionary, &copy
        )
        guard status == kCVReturnSuccess, let copy else { return nil }

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
