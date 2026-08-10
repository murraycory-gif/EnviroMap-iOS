import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// 3D Snap–style output: LiDAR mesh + real camera photos projected onto it.
/// Unscanned areas stay empty (black) — no fake fill.
enum PhotoTexturedMeshBuilder {

    struct Keyframe {
        let camera: ARCamera
        let orientation: UIInterfaceOrientation
        let viewport: CGSize
        let displayTransform: CGAffineTransform
        let capturedAt: TimeInterval
        let rgb: [UInt8]
        let rgbWidth: Int
        let rgbHeight: Int
        let camPos: SIMD3<Float>
        /// May be empty during live scan; rebuilt from `rgb` at bake.
        let image: UIImage
    }

    struct BuildResult {
        let scene: SCNScene
        let fileName: String
    }

    static var progressHandler: ((Double, String) -> Void)?

    static func makeScene(chunks: [CapturedMeshChunk], keyframes: [Keyframe]) -> SCNScene? {
        buildScene(chunks: chunks, keyframes: keyframes)
    }

    static func writeScene(_ scene: SCNScene, to directory: URL, name: String = "room_full.scn") -> String? {
        // Write textures next to scene so reload shows real photos
        let mesh = scene.rootNode.childNode(withName: "coloredMesh", recursively: true)
        mesh?.enumerateChildNodes { node, _ in
            guard let mat = node.geometry?.firstMaterial,
                  let img = mat.diffuse.contents as? UIImage,
                  let nameHint = node.name, nameHint.hasPrefix("texChunk_") else { return }
            let file = "\(nameHint).jpg"
            let url = directory.appendingPathComponent(file)
            if let data = img.jpegData(compressionQuality: 0.88) {
                try? data.write(to: url)
                // Keep in-memory image for Review; path helps disk reload
                mat.diffuse.contents = img
            }
        }
        let url = directory.appendingPathComponent(name)
        if scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) {
            return name
        }
        return nil
    }

    static func buildAndExport(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe],
        to directory: URL
    ) -> BuildResult? {
        guard let scene = buildScene(chunks: chunks, keyframes: keyframes) else { return nil }
        let name = writeScene(scene, to: directory) ?? "room_full.scn"
        return BuildResult(scene: scene, fileName: name)
    }

    static func exportChunks(
        _ chunks: [CapturedMeshChunk],
        keyframes: [Keyframe],
        to directory: URL,
        name: String = "room_full.scn"
    ) -> String? {
        buildAndExport(chunks: chunks, keyframes: keyframes, to: directory)?.fileName
    }

    // MARK: - Build (photo-projected mesh)

    private static func buildScene(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe]
    ) -> SCNScene? {
        guard !chunks.isEmpty, !keyframes.isEmpty else { return nil }

        progressHandler?(0.05, "Preparing camera photos…")

        // Rebuild UIImages from RGB (live capture skipped full UIImage for speed)
        let kfs = selectKeyframes(keyframes, limit: MeshDensityConfig.bakeKeyframeLimit).compactMap { kf -> Keyframe? in
            let img: UIImage
            if kf.image.size.width > 2 {
                img = kf.image
            } else if let built = uiImage(rgb: kf.rgb, width: kf.rgbWidth, height: kf.rgbHeight) {
                img = built
            } else {
                return nil
            }
            return Keyframe(
                camera: kf.camera,
                orientation: kf.orientation,
                viewport: kf.viewport,
                displayTransform: kf.displayTransform,
                capturedAt: kf.capturedAt,
                rgb: kf.rgb,
                rgbWidth: kf.rgbWidth,
                rgbHeight: kf.rgbHeight,
                camPos: kf.camPos,
                image: img
            )
        }
        guard !kfs.isEmpty else { return nil }

        progressHandler?(0.15, "Projecting photos onto mesh…")

        let scene = SCNScene()
        // 3D Snap style: pure black voids where not scanned
        scene.background.contents = UIColor.black

        let root = SCNNode()
        root.name = "coloredMesh"

        let total = max(chunks.count, 1)
        var nodeCount = 0

        for (ci, chunk) in chunks.enumerated() {
            if ci % 4 == 0 {
                let p = 0.15 + 0.7 * (Double(ci) / Double(total))
                progressHandler?(p, "Texturing surfaces…")
            }
            if let node = makePhotoTexturedChunk(chunk: chunk, keyframes: kfs, index: ci) {
                root.addChildNode(node)
                nodeCount += 1
            }
        }

        guard nodeCount > 0 else {
            progressHandler?(1, "No textured surfaces")
            return nil
        }

        scene.rootNode.addChildNode(root)

        let ambient = SCNNode()
        ambient.name = "viewerAmbient"
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1200
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        progressHandler?(0.92, "Framing view…")
        normalizeForPreview(scene)
        progressHandler?(1.0, "Ready")
        return scene
    }

    /// Mesh tile textured from real camera photos (multi-view, 3D Snap style).
    private static func makePhotoTexturedChunk(
        chunk: CapturedMeshChunk,
        keyframes: [Keyframe],
        index: Int
    ) -> SCNNode? {
        let vCount = chunk.positions.count
        let triCount = chunk.indices.count / 3
        guard vCount >= 3, triCount > 0 else { return nil }

        let t = chunk.transform
        func world(_ i: Int) -> SIMD3<Float> {
            let p = chunk.positions[i]
            let w = t * SIMD4<Float>(p.x, p.y, p.z, 1)
            return SIMD3(w.x, w.y, w.z)
        }

        let triStep = triCount > 50_000 ? 2 : 1

        // Group triangles by best keyframe index
        var groups: [Int: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)]] = [:]

        for ti in stride(from: 0, to: triCount, by: triStep) {
            let i0 = Int(chunk.indices[ti * 3])
            let i1 = Int(chunk.indices[ti * 3 + 1])
            let i2 = Int(chunk.indices[ti * 3 + 2])
            guard i0 < vCount, i1 < vCount, i2 < vCount else { continue }

            let w0 = world(i0), w1 = world(i1), w2 = world(i2)
            let cross = simd_cross(w1 - w0, w2 - w0)
            let area = simd_length(cross)
            if area < 1e-9 { continue }
            var n = cross / area
            if n.x.isNaN { n = SIMD3(0, 1, 0) }

            let c = (w0 + w1 + w2) / 3
            guard let (kfIdx, kf) = bestKeyframeIndex(for: c, keyframes: keyframes) else { continue }
            guard let uv0 = projectUV(world: w0, kf: kf),
                  let uv1 = projectUV(world: w1, kf: kf),
                  let uv2 = projectUV(world: w2, kf: kf) else { continue }

            let du1 = abs(uv0.x - uv1.x) + abs(uv0.y - uv1.y)
            let du2 = abs(uv1.x - uv2.x) + abs(uv1.y - uv2.y)
            let du3 = abs(uv2.x - uv0.x) + abs(uv2.y - uv0.y)
            if du1 > 0.9 || du2 > 0.9 || du3 > 0.9 { continue }

            groups[kfIdx, default: []].append((w0, w1, w2, n, uv0, uv1, uv2))
        }

        guard !groups.isEmpty else { return nil }

        let parent = SCNNode()
        parent.name = "texChunk_\(index)"

        for (kfIdx, tris) in groups {
            guard kfIdx < keyframes.count, !tris.isEmpty else { continue }
            let kf = keyframes[kfIdx]
            var positions: [Float] = []
            var normals: [Float] = []
            var uvs: [Float] = []
            var indices: [UInt32] = []
            positions.reserveCapacity(tris.count * 9)
            var vi: UInt32 = 0
            let limit = min(tris.count, 20_000)
            for tri in tris.prefix(limit) {
                let (w0, w1, w2, n, uv0, uv1, uv2) = tri
                for (w, uv) in [(w0, uv0), (w1, uv1), (w2, uv2)] {
                    positions.append(contentsOf: [w.x, w.y, w.z])
                    normals.append(contentsOf: [n.x, n.y, n.z])
                    uvs.append(contentsOf: [uv.x, uv.y])
                    indices.append(vi)
                    vi += 1
                }
            }
            guard !positions.isEmpty else { continue }

            let posData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
            let nrmData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
            let uvData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
            let idxData = indices.withUnsafeBufferPointer { Data(buffer: $0) }

            let sources = [
                SCNGeometrySource(
                    data: posData, semantic: .vertex, vectorCount: positions.count / 3,
                    usesFloatComponents: true, componentsPerVector: 3,
                    bytesPerComponent: 4, dataOffset: 0, dataStride: 12
                ),
                SCNGeometrySource(
                    data: nrmData, semantic: .normal, vectorCount: normals.count / 3,
                    usesFloatComponents: true, componentsPerVector: 3,
                    bytesPerComponent: 4, dataOffset: 0, dataStride: 12
                ),
                SCNGeometrySource(
                    data: uvData, semantic: .texcoord, vectorCount: uvs.count / 2,
                    usesFloatComponents: true, componentsPerVector: 2,
                    bytesPerComponent: 4, dataOffset: 0, dataStride: 8
                ),
            ]
            let element = SCNGeometryElement(
                data: idxData, primitiveType: .triangles,
                primitiveCount: indices.count / 3, bytesPerIndex: 4
            )
            let geom = SCNGeometry(sources: sources, elements: [element])
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.fillMode = .fill
            mat.writesToDepthBuffer = true
            mat.diffuse.contents = kf.image
            mat.diffuse.wrapS = .clamp
            mat.diffuse.wrapT = .clamp
            mat.diffuse.magnificationFilter = .linear
            mat.diffuse.minificationFilter = .linear
            geom.materials = [mat]
            let node = SCNNode(geometry: geom)
            node.name = "texChunk_\(index)_\(kfIdx)"
            parent.addChildNode(node)
        }

        return parent.childNodes.isEmpty ? nil : parent
    }

    private static func bestKeyframeIndex(for world: SIMD3<Float>, keyframes: [Keyframe]) -> (Int, Keyframe)? {
        var bestI = -1
        var bestKF: Keyframe?
        var bestScore: Float = -1
        for (i, kf) in keyframes.enumerated().reversed() {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            if dist < 0.08 || dist > 12 { continue }
            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.05 { continue }
            let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
            guard projected.x.isFinite, projected.y.isFinite else { continue }
            let nx = projected.x / max(kf.viewport.width, 1)
            let ny = projected.y / max(kf.viewport.height, 1)
            guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { continue }
            let score = (1.0 / max(dist, 0.2)) * (1.0 - abs(nx - 0.5)) * (1.0 - abs(ny - 0.5))
            if score > bestScore {
                bestScore = score
                bestI = i
                bestKF = kf
            }
        }
        if let bestKF, bestI >= 0 { return (bestI, bestKF) }
        return nil
    }

    // Dummy for compiler - not used for limit calc
    private static let chunksEstimatePlaceholder = 40

    // MARK: - Projection

    private static func bestKeyframe(for world: SIMD3<Float>, keyframes: [Keyframe]) -> Keyframe? {
        var best: Keyframe?
        var bestScore: Float = -1
        for kf in keyframes.reversed() {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            if dist < 0.08 || dist > 12 { continue }
            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.05 { continue }
            let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
            guard projected.x.isFinite, projected.y.isFinite else { continue }
            let nx = projected.x / max(kf.viewport.width, 1)
            let ny = projected.y / max(kf.viewport.height, 1)
            guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { continue }
            let score = (1.0 / max(dist, 0.2)) * (1.0 - abs(nx - 0.5)) * (1.0 - abs(ny - 0.5))
            if score > bestScore {
                bestScore = score
                best = kf
            }
        }
        return best
    }

    private static func projectUV(world: SIMD3<Float>, kf: Keyframe) -> SIMD2<Float>? {
        let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
        if view.z > -0.02 { return nil }

        let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
        guard projected.x.isFinite, projected.y.isFinite else { return nil }

        let nx = projected.x / max(kf.viewport.width, 1)
        let ny = projected.y / max(kf.viewport.height, 1)
        guard nx >= -0.02, nx <= 1.02, ny >= -0.02, ny <= 1.02 else { return nil }

        var uv = CGPoint(x: CGFloat(min(max(nx, 0), 1)), y: CGFloat(min(max(ny, 0), 1)))
            .applying(kf.displayTransform.inverted())

        // SceneKit UV origin bottom-left; displayTransform often top-left — flip Y if needed
        if uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1 {
            // try without invert
            uv = CGPoint(x: CGFloat(min(max(nx, 0), 1)), y: CGFloat(min(max(ny, 0), 1)))
        }
        guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { return nil }

        // UIImage textures in SceneKit: v=0 at bottom
        let u = Float(uv.x)
        let v = Float(1.0 - uv.y)
        return SIMD2(u, v)
    }

    // MARK: - Normalize / camera (Review + RoomViewer)

    static func normalizeForPreview(_ scene: SCNScene) {
        if scene.rootNode.userData?["enviromap.normalized"] as? Bool == true,
           scene.rootNode.childNode(withName: "previewCam", recursively: true) != nil {
            return
        }

        let mesh = scene.rootNode.childNode(withName: "coloredMesh", recursively: true) ?? scene.rootNode

        var minV = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxV = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        var found = false

        func visit(_ node: SCNNode) {
            if let g = node.geometry {
                let (bmin, bmax) = g.boundingBox
                for sx: Float in [0, 1] {
                    for sy: Float in [0, 1] {
                        for sz: Float in [0, 1] {
                            let lx = bmin.x + (bmax.x - bmin.x) * sx
                            let ly = bmin.y + (bmax.y - bmin.y) * sy
                            let lz = bmin.z + (bmax.z - bmin.z) * sz
                            let w = node.convertPosition(SCNVector3(lx, ly, lz), to: scene.rootNode)
                            minV = simd_min(minV, SIMD3(w.x, w.y, w.z))
                            maxV = simd_max(maxV, SIMD3(w.x, w.y, w.z))
                            found = true
                        }
                    }
                }
            }
            for c in node.childNodes { visit(c) }
        }
        visit(mesh)
        guard found else { return }

        let center = (minV + maxV) * 0.5
        let extent = max(maxV.x - minV.x, max(maxV.y - minV.y, maxV.z - minV.z))
        let safeExtent = max(extent, 0.4)

        if let colored = scene.rootNode.childNode(withName: "coloredMesh", recursively: false) {
            colored.position = SCNVector3(-center.x, -center.y, -center.z)
        }

        scene.rootNode.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }

        let dist = safeExtent * 2.1
        let cam = SCNNode()
        cam.name = "previewCam"
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 50
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = max(200, Double(safeExtent * 40))
        cam.position = SCNVector3(dist * 0.5, dist * 0.35, dist * 0.95)
        cam.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cam)

        if scene.rootNode.childNode(withName: "viewerAmbient", recursively: false) == nil {
            let amb = SCNNode()
            amb.name = "viewerAmbient"
            amb.light = SCNLight()
            amb.light?.type = .ambient
            amb.light?.intensity = 1400
            scene.rootNode.addChildNode(amb)
        }

        scene.background.contents = UIColor.black

        // Keep photo materials as photos
        func paint(_ node: SCNNode) {
            if let mats = node.geometry?.materials {
                for m in mats {
                    m.lightingModel = .constant
                    m.isDoubleSided = true
                    m.fillMode = .fill
                }
            }
            for c in node.childNodes { paint(c) }
        }
        paint(scene.rootNode)

        if scene.rootNode.userData == nil { scene.rootNode.userData = NSMutableDictionary() }
        scene.rootNode.userData?["enviromap.normalized"] = true
    }

    // MARK: - Keyframe capture

    private static func selectKeyframes(_ all: [Keyframe], limit: Int) -> [Keyframe] {
        guard !all.isEmpty else { return [] }
        guard all.count > limit else { return all }
        var result: [Keyframe] = []
        let recent = min((limit * 3) / 4, all.count)
        result.append(contentsOf: all.suffix(recent))
        let older = Array(all.dropLast(recent))
        let need = limit - result.count
        if need > 0, !older.isEmpty {
            for i in 0..<need {
                let idx = i * older.count / need
                result.append(older[min(idx, older.count - 1)])
            }
        }
        return result
    }

    static func makeKeyframe(
        from frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewport: CGSize,
        maxWidth: Int = MeshDensityConfig.keyframeMaxWidth
    ) -> Keyframe? {
        guard let (rgb, w, h) = extractRGB(buffer: frame.capturedImage, maxWidth: maxWidth) else { return nil }
        // Live: skip full UIImage (memory). Bake rebuilds from rgb.
        let cam = frame.camera
        let camPos = SIMD3<Float>(
            cam.transform.columns.3.x,
            cam.transform.columns.3.y,
            cam.transform.columns.3.z
        )
        return Keyframe(
            camera: cam,
            orientation: orientation,
            viewport: viewport,
            displayTransform: frame.displayTransform(for: orientation, viewportSize: viewport),
            capturedAt: frame.timestamp,
            rgb: rgb,
            rgbWidth: w,
            rgbHeight: h,
            camPos: camPos,
            image: UIImage()
        )
    }

    private static func uiImage(rgb: [UInt8], width: Int, height: Int) -> UIImage? {
        guard width > 1, height > 1, rgb.count >= width * height * 3 else { return nil }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = rgb[i * 3]
            rgba[i * 4 + 1] = rgb[i * 3 + 1]
            rgba[i * 4 + 2] = rgb[i * 3 + 2]
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func extractRGB(buffer: CVPixelBuffer, maxWidth: Int) -> ([UInt8], Int, Int)? {
        let fullW = CVPixelBufferGetWidth(buffer)
        let fullH = CVPixelBufferGetHeight(buffer)
        guard fullW > 1, fullH > 1 else { return nil }

        let scale = min(1.0, CGFloat(maxWidth) / CGFloat(fullW))
        let w = max(2, Int(CGFloat(fullW) * scale))
        let h = max(2, Int(CGFloat(fullH) * scale))

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let format = CVPixelBufferGetPixelFormatType(buffer)
        var rgb = [UInt8](repeating: 0, count: w * h * 3)

        if format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
                  let cBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
            let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let cStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let videoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

            for j in 0..<h {
                let sy = min(Int(CGFloat(j) / scale), fullH - 1)
                for i in 0..<w {
                    let sx = min(Int(CGFloat(i) / scale), fullW - 1)
                    let Y = Float(yBase.advanced(by: sy * yStride + sx).assumingMemoryBound(to: UInt8.self).pointee)
                    let cPtr = cBase.advanced(by: (sy / 2) * cStride + (sx / 2) * 2).assumingMemoryBound(to: UInt8.self)
                    let Cb = Float(cPtr[0]) - 128
                    let Cr = Float(cPtr[1]) - 128
                    let yf = videoRange ? (Y - 16) * (255.0 / 219.0) : Y
                    var r = yf + 1.402 * Cr
                    var g = yf - 0.344136 * Cb - 0.714136 * Cr
                    var b = yf + 1.772 * Cb
                    r = min(max(r, 0), 255); g = min(max(g, 0), 255); b = min(max(b, 0), 255)
                    let o = (j * w + i) * 3
                    rgb[o] = UInt8(r); rgb[o + 1] = UInt8(g); rgb[o + 2] = UInt8(b)
                }
            }
            return (rgb, w, h)
        }

        if format == kCVPixelFormatType_32BGRA {
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for j in 0..<h {
                let sy = min(Int(CGFloat(j) / scale), fullH - 1)
                for i in 0..<w {
                    let sx = min(Int(CGFloat(i) / scale), fullW - 1)
                    let p = base.advanced(by: sy * stride + sx * 4).assumingMemoryBound(to: UInt8.self)
                    let o = (j * w + i) * 3
                    rgb[o] = p[2]; rgb[o + 1] = p[1]; rgb[o + 2] = p[0]
                }
            }
            return (rgb, w, h)
        }
        return nil
    }
}
