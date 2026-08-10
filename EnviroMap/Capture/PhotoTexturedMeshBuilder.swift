import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// LiDAR mesh + multi-view camera colors (vertex colors).
/// Vertex colors are more reliable than UV photo projection and look like real objects.
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

    // MARK: - Build

    private static func buildScene(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe]
    ) -> SCNScene? {
        guard !chunks.isEmpty else { return nil }
        progressHandler?(0.08, "Coloring mesh…")

        let kfs = selectKeyframes(keyframes, limit: MeshDensityConfig.bakeKeyframeLimit)
        let scene = SCNScene()
        scene.background.contents = UIColor.black

        let root = SCNNode()
        root.name = "coloredMesh"

        // Merge into one geometry for clarity + faster load
        var allPos: [Float] = []
        var allNrm: [Float] = []
        var allCol: [Float] = []
        var allIdx: [UInt32] = []
        var base: UInt32 = 0

        let total = max(chunks.count, 1)
        let triBudget = MeshDensityConfig.triangleBudget
        var triUsed = 0

        for (ci, chunk) in chunks.enumerated() {
            if ci % 3 == 0 {
                progressHandler?(0.1 + 0.75 * Double(ci) / Double(total), "Painting surfaces…")
            }
            if triUsed >= triBudget { break }

            let vCount = chunk.positions.count
            let triCount = chunk.indices.count / 3
            guard vCount >= 3, triCount > 0 else { continue }

            let t = chunk.transform
            func world(_ i: Int) -> SIMD3<Float> {
                let p = chunk.positions[i]
                let w = t * SIMD4<Float>(p.x, p.y, p.z, 1)
                return SIMD3(w.x, w.y, w.z)
            }

            // Adaptive step: keep denser mesh for smaller chunks (detail objects)
            let triStep: Int
            if triCount > 80_000 { triStep = 3 }
            else if triCount > 40_000 { triStep = 2 }
            else { triStep = 1 }

            var localMap: [Int: UInt32] = [:]

            func ensureVertex(_ vi: Int) -> UInt32 {
                if let existing = localMap[vi] { return existing }
                let w = world(vi)
                let n: SIMD3<Float>
                if vi < chunk.normals.count {
                    let ln = chunk.normals[vi]
                    let nw = t * SIMD4<Float>(ln.x, ln.y, ln.z, 0)
                    var nn = SIMD3(nw.x, nw.y, nw.z)
                    let len = simd_length(nn)
                    n = len > 1e-6 ? nn / len : SIMD3(0, 1, 0)
                } else {
                    n = SIMD3(0, 1, 0)
                }
                let rgb = colorFor(world: w, normal: n, keyframes: kfs)

                allPos.append(contentsOf: [w.x, w.y, w.z])
                allNrm.append(contentsOf: [n.x, n.y, n.z])
                allCol.append(contentsOf: [
                    Float(rgb.0) / 255.0,
                    Float(rgb.1) / 255.0,
                    Float(rgb.2) / 255.0,
                    1.0
                ])
                let id = base
                base += 1
                localMap[vi] = id
                return id
            }

            for ti in stride(from: 0, to: triCount, by: triStep) {
                if triUsed >= triBudget { break }
                let i0 = Int(chunk.indices[ti * 3])
                let i1 = Int(chunk.indices[ti * 3 + 1])
                let i2 = Int(chunk.indices[ti * 3 + 2])
                guard i0 < vCount, i1 < vCount, i2 < vCount else { continue }

                let w0 = world(i0), w1 = world(i1), w2 = world(i2)
                let cross = simd_cross(w1 - w0, w2 - w0)
                if simd_length(cross) < 1e-9 { continue }

                let a = ensureVertex(i0)
                let b = ensureVertex(i1)
                let c = ensureVertex(i2)
                if a == b || b == c || a == c { continue }
                allIdx.append(contentsOf: [a, b, c])
                triUsed += 1
            }
        }

        guard !allPos.isEmpty, !allIdx.isEmpty else {
            progressHandler?(1, "No mesh")
            return nil
        }

        progressHandler?(0.9, "Building 3D view…")

        let posData = allPos.withUnsafeBufferPointer { Data(buffer: $0) }
        let nrmData = allNrm.withUnsafeBufferPointer { Data(buffer: $0) }
        let colData = allCol.withUnsafeBufferPointer { Data(buffer: $0) }
        let idxData = allIdx.withUnsafeBufferPointer { Data(buffer: $0) }

        let sources = [
            SCNGeometrySource(
                data: posData, semantic: .vertex, vectorCount: allPos.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            ),
            SCNGeometrySource(
                data: nrmData, semantic: .normal, vectorCount: allNrm.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            ),
            SCNGeometrySource(
                data: colData, semantic: .color, vectorCount: allCol.count / 4,
                usesFloatComponents: true, componentsPerVector: 4,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 16
            ),
        ]
        let element = SCNGeometryElement(
            data: idxData, primitiveType: .triangles,
            primitiveCount: allIdx.count / 3, bytesPerIndex: 4
        )
        let geom = SCNGeometry(sources: sources, elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.fillMode = .fill
        mat.writesToDepthBuffer = true
        // Vertex colors drive appearance
        mat.diffuse.contents = UIColor.white
        geom.materials = [mat]

        let node = SCNNode(geometry: geom)
        node.name = "vertexColoredMesh"
        root.addChildNode(node)
        scene.rootNode.addChildNode(root)

        let ambient = SCNNode()
        ambient.name = "viewerAmbient"
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1400
        scene.rootNode.addChildNode(ambient)

        normalizeForPreview(scene)
        progressHandler?(1.0, "Ready")
        return scene
    }

    /// Multi-view weighted average of camera colors (sharper than single sample).
    private static func colorFor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8) {
        guard !keyframes.isEmpty else { return (170, 175, 180) }

        var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0, wSum: Float = 0
        // Prefer recent keyframes (often better aimed)
        let list = keyframes.reversed()
        var hits = 0

        for kf in list {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            if dist < 0.05 || dist > 10 { continue }

            // Facing camera?
            let viewDir = toCam / max(dist, 1e-4)
            let facing = simd_dot(normal, viewDir)
            if facing < 0.05 { continue }

            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.02 { continue }

            let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
            guard projected.x.isFinite, projected.y.isFinite else { continue }
            let vpW = max(Float(kf.viewport.width), 1)
            let vpH = max(Float(kf.viewport.height), 1)
            let nx = Float(projected.x) / vpW
            let ny = Float(projected.y) / vpH
            guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { continue }

            let x0 = Int(nx * Float(kf.rgbWidth - 1))
            let y0 = Int(ny * Float(kf.rgbHeight - 1))
            guard let c = sample(kf, x0, y0) else { continue }

            // Weight: closer + more face-on + more centered
            let center = (1 - abs(nx - 0.5)) * (1 - abs(ny - 0.5))
            let w = (facing * facing) * (1.0 / max(dist, 0.2)) * (0.4 + 0.6 * center)
            rSum += Float(c.0) * w
            gSum += Float(c.1) * w
            bSum += Float(c.2) * w
            wSum += w
            hits += 1
            if hits >= 6 { break } // enough blend
        }

        if wSum < 1e-5 {
            // Fallback: nearest keyframe color at center sample
            if let kf = keyframes.last, let c = sample(kf, kf.rgbWidth / 2, kf.rgbHeight / 2) {
                return c
            }
            return (150, 155, 160)
        }
        return (
            UInt8(min(255, max(0, rSum / wSum))),
            UInt8(min(255, max(0, gSum / wSum))),
            UInt8(min(255, max(0, bSum / wSum)))
        )
    }

    private static func sample(_ kf: Keyframe, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)? {
        let xx = min(max(x, 0), kf.rgbWidth - 1)
        let yy = min(max(y, 0), kf.rgbHeight - 1)
        let o = (yy * kf.rgbWidth + xx) * 3
        guard o + 2 < kf.rgb.count else { return nil }
        return (kf.rgb[o], kf.rgb[o + 1], kf.rgb[o + 2])
    }

    // MARK: - Normalize / camera

    static func normalizeForPreview(_ scene: SCNScene) {
        if scene.rootNode.childNode(withName: "enviromap.normalized.flag", recursively: false) != nil,
           scene.rootNode.childNode(withName: "previewCam", recursively: true) != nil {
            return
        }

        let mesh = scene.rootNode.childNode(withName: "coloredMesh", recursively: true) ?? scene.rootNode

        var minV = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxV = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
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
                            if w.x.isFinite {
                                minV = simd_min(minV, SIMD3(w.x, w.y, w.z))
                                maxV = simd_max(maxV, SIMD3(w.x, w.y, w.z))
                                found = true
                            }
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
        let safe = max(extent, 0.35)

        if let colored = scene.rootNode.childNode(withName: "coloredMesh", recursively: false) {
            colored.position = SCNVector3(-center.x, -center.y, -center.z)
        }

        scene.rootNode.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }

        let dist = safe * 2.2
        let cam = SCNNode()
        cam.name = "previewCam"
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 50
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = max(200, Double(safe * 40))
        cam.position = SCNVector3(dist * 0.55, dist * 0.4, dist * 0.95)
        cam.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cam)

        if scene.rootNode.childNode(withName: "viewerAmbient", recursively: false) == nil {
            let amb = SCNNode()
            amb.name = "viewerAmbient"
            amb.light = SCNLight()
            amb.light?.type = .ambient
            amb.light?.intensity = 1500
            scene.rootNode.addChildNode(amb)
        }

        scene.background.contents = UIColor.black
        if scene.rootNode.childNode(withName: "enviromap.normalized.flag", recursively: false) == nil {
            let flag = SCNNode()
            flag.name = "enviromap.normalized.flag"
            flag.isHidden = true
            scene.rootNode.addChildNode(flag)
        }
    }

    // MARK: - Keyframes

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

    private static func extractRGB(buffer: CVPixelBuffer, maxWidth: Int) -> ([UInt8], Int, Int)? {
        let fullW = CVPixelBufferGetWidth(buffer)
        let fullH = CVPixelBufferGetHeight(buffer)
        guard fullW > 1, fullH > 1 else { return nil }

        let scale = min(1.0 as CGFloat, CGFloat(maxWidth) / CGFloat(max(fullW, 1)))
        let w = max(2, Int((CGFloat(fullW) * scale).rounded(.down)))
        let h = max(2, Int((CGFloat(fullH) * scale).rounded(.down)))

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
                let sy = min(Int((CGFloat(j) / max(scale, 0.0001)).rounded(.down)), fullH - 1)
                for i in 0..<w {
                    let sx = min(Int((CGFloat(i) / max(scale, 0.0001)).rounded(.down)), fullW - 1)
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
                let sy = min(Int((CGFloat(j) / max(scale, 0.0001)).rounded(.down)), fullH - 1)
                for i in 0..<w {
                    let sx = min(Int((CGFloat(i) / max(scale, 0.0001)).rounded(.down)), fullW - 1)
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
