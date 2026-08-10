import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Dense multi-view colored LiDAR mesh.
/// Optimized so Done never hangs: triangle budget + few keyframes + fast sampling.
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

    /// Optional progress 0...1 on calling thread (often background).
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

    
    /// Centers mesh at origin and installs a reliable orbit camera (fixes black Review).
    static func normalizeForPreview(_ scene: SCNScene) {
        if scene.rootNode.userData?["enviromap.normalized"] as? Bool == true {
            // Still ensure camera exists
            if scene.rootNode.childNode(withName: "previewCam", recursively: true) == nil {
                // fall through to camera setup only — reset flag temporarily
                scene.rootNode.userData?["enviromap.normalized"] = false
            } else {
                return
            }
        }
        let mesh = scene.rootNode.childNode(withName: "coloredMesh", recursively: true) ?? scene.rootNode

        // Compute world bounds from geometry
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
        let safeExtent = max(extent, 0.5)

        // Shift mesh so center is origin
        if let colored = scene.rootNode.childNode(withName: "coloredMesh", recursively: false) {
            colored.position = SCNVector3(-center.x, -center.y, -center.z)
        } else {
            mesh.position = SCNVector3(
                mesh.position.x - center.x,
                mesh.position.y - center.y,
                mesh.position.z - center.z
            )
        }

        // Remove prior cameras
        scene.rootNode.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }

        let dist = safeExtent * 2.2
        let cam = SCNNode()
        cam.name = "previewCam"
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 55
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = max(200, Double(safeExtent * 40))
        // Classic 3/4 view — always frames origin-centered mesh
        cam.position = SCNVector3(dist * 0.55, dist * 0.4, dist * 0.95)
        cam.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cam)

        // Ensure ambient light
        if scene.rootNode.childNode(withName: "viewerAmbient", recursively: false) == nil {
            let amb = SCNNode()
            amb.name = "viewerAmbient"
            amb.light = SCNLight()
            amb.light?.type = .ambient
            amb.light?.intensity = 1400
            amb.light?.color = UIColor.white
            scene.rootNode.addChildNode(amb)
        }

        scene.background.contents = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)

        // Force solid fill materials
        func paint(_ node: SCNNode) {
            if let mats = node.geometry?.materials {
                for m in mats {
                    m.lightingModel = .constant
                    m.isDoubleSided = true
                    m.fillMode = .fill
                    if m.diffuse.contents == nil {
                        m.diffuse.contents = UIColor(white: 0.75, alpha: 1)
                    }
                }
            }
            for c in node.childNodes { paint(c) }
        }
        paint(scene.rootNode)
        if scene.rootNode.userData == nil { scene.rootNode.userData = NSMutableDictionary() }
        scene.rootNode.userData?["enviromap.normalized"] = true
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

        progressHandler?(0.05, "Gathering surfaces…")

        // Prefer recent, well-spaced frames (fast + sharp)
        let kfs = selectKeyframes(keyframes, limit: MeshDensityConfig.bakeKeyframeLimit)
        // If no keyframes, still build gray mesh so user sees shape
        let hasColor = !kfs.isEmpty

        struct Tri {
            let w0, w1, w2: SIMD3<Float>
            let normal: SIMD3<Float>
        }

        var tris: [Tri] = []
        var est = 0
        for c in chunks { est += c.indices.count / 3 }
        tris.reserveCapacity(min(est, MeshDensityConfig.triangleBudget + 20_000))

        // Global triangle budget — prevents freeze/OOM, keeps objects
        let budget = MeshDensityConfig.triangleBudget
        let strideTri = est > budget ? max(1, (est + budget - 1) / budget) : 1

        for chunk in chunks {
            let t = chunk.transform
            let vCount = chunk.positions.count
            guard vCount > 0 else { continue }
            let triCount = chunk.indices.count / 3

            for ti in stride(from: 0, to: triCount, by: strideTri) {
                let i0 = Int(chunk.indices[ti * 3])
                let i1 = Int(chunk.indices[ti * 3 + 1])
                let i2 = Int(chunk.indices[ti * 3 + 2])
                guard i0 < vCount, i1 < vCount, i2 < vCount else { continue }

                func world(_ i: Int) -> SIMD3<Float> {
                    let p = chunk.positions[i]
                    let w = t * SIMD4<Float>(p.x, p.y, p.z, 1)
                    return SIMD3(w.x, w.y, w.z)
                }

                let w0 = world(i0), w1 = world(i1), w2 = world(i2)
                let cross = simd_cross(w1 - w0, w2 - w0)
                let area = simd_length(cross)
                if area < 1e-9 { continue }
                var n = cross / area
                if n.x.isNaN || n.x.isInfinite { n = SIMD3(0, 1, 0) }
                tris.append(Tri(w0: w0, w1: w1, w2: w2, normal: n))
            }
        }

        guard !tris.isEmpty else {
            progressHandler?(1, "No geometry")
            return nil
        }

        progressHandler?(0.25, "Painting real colors…")

        let triCount = tris.count
        var colors = [(UInt8, UInt8, UInt8)](repeating: (170, 170, 170), count: triCount)

        if hasColor {
            // Chunk concurrent work into batches for progress updates
            let batch = max(1, triCount / 20)
            DispatchQueue.concurrentPerform(iterations: triCount) { i in
                let tri = tris[i]
                colors[i] = colorForTriangle(tri.w0, tri.w1, tri.w2, normal: tri.normal, keyframes: kfs)
                if i % batch == 0 {
                    let p = 0.25 + 0.55 * (Double(i) / Double(triCount))
                    progressHandler?(p, "Painting real colors…")
                }
            }
        } else {
            // Height-based false color so mesh is never empty white
            for i in 0..<triCount {
                let y = (tris[i].w0.y + tris[i].w1.y + tris[i].w2.y) / 3
                let t = min(max((y + 0.5) / 2.5, 0), 1)
                colors[i] = (
                    UInt8(80 + 100 * t),
                    UInt8(120 + 80 * (1 - t)),
                    UInt8(180 - 60 * t)
                )
            }
        }

        progressHandler?(0.82, "Building 3D model…")

        // 5-bit quantize — fewer materials = faster SceneKit, still colorful
        var groups: [UInt32: [Float]] = [:]
        var groupRGB: [UInt32: (UInt8, UInt8, UInt8)] = [:]
        groups.reserveCapacity(min(triCount / 3, 4000))

        for i in 0..<triCount {
            let tri = tris[i]
            let rgb = colors[i]
            let key = quantize(rgb)
            groupRGB[key] = rgb
            var arr = groups[key] ?? []
            arr.append(contentsOf: [
                tri.w0.x, tri.w0.y, tri.w0.z,
                tri.w1.x, tri.w1.y, tri.w1.z,
                tri.w2.x, tri.w2.y, tri.w2.z
            ])
            groups[key] = arr
        }

        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1)

        let root = SCNNode()
        root.name = "coloredMesh"

        for (key, floats) in groups {
            let rgb = groupRGB[key] ?? (160, 160, 160)
            if let node = solidMeshNode(positions: floats, color: rgb) {
                root.addChildNode(node)
            }
        }

        // Guarantee something visible
        if root.childNodes.isEmpty {
            progressHandler?(1, "Failed")
            return nil
        }

        scene.rootNode.addChildNode(root)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1000
        scene.rootNode.addChildNode(ambient)

        // Fit camera to mesh bounds
        let (minB, maxB) = root.boundingBox
        let mid = SCNVector3(
            (minB.x + maxB.x) * 0.5,
            (minB.y + maxB.y) * 0.5,
            (minB.z + maxB.z) * 0.5
        )
        let ext = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z, 0.5)
        let cam = SCNNode()
        cam.name = "previewCam"
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 55
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 500
        cam.position = SCNVector3(mid.x + ext * 0.55, mid.y + ext * 0.4, mid.z + ext * 1.1)
        cam.eulerAngles = SCNVector3(Float(-0.3), Float(0.4), Float(0))
        scene.rootNode.addChildNode(cam)

        progressHandler?(0.95, "Framing view…")
        normalizeForPreview(scene)
        progressHandler?(1.0, "Ready")
        return scene
    }

    // MARK: - Color

    private static func colorForTriangle(
        _ w0: SIMD3<Float>,
        _ w1: SIMD3<Float>,
        _ w2: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8) {
        let c = (w0 + w1 + w2) / 3
        // Density-aware samples (more = sharper object colors)
        let pts: [SIMD3<Float>] = MeshDensityConfig.samplesPerTriangle >= 5
            ? [c, w0, w1, w2, (w0 + w1) * 0.5]
            : [c, w0, w1, w2]
        var r = 0, g = 0, b = 0, n = 0
        for p in pts {
            if let s = sampleBestColor(world: p, normal: normal, keyframes: keyframes) {
                r += Int(s.0); g += Int(s.1); b += Int(s.2)
                n += 1
            }
        }
        if n > 0 {
            return (UInt8(r / n), UInt8(g / n), UInt8(b / n))
        }
        // Height tint fallback (never pure white void)
        let y = c.y
        let t = min(max((y + 0.2) / 2.0, 0), 1)
        return (
            UInt8(90 + 90 * t),
            UInt8(100 + 60 * (1 - t)),
            UInt8(140 + 40 * t)
        )
    }

    private static func sampleBestColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8)? {
        var best: (UInt8, UInt8, UInt8)?
        var bestScore: Float = -1

        // Recent frames first
        for kf in keyframes.reversed() {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            if dist < 0.06 || dist > 12 { continue }

            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.02 { continue }

            let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
            guard projected.x.isFinite, projected.y.isFinite else { continue }

            let nx = projected.x / max(kf.viewport.width, 1)
            let ny = projected.y / max(kf.viewport.height, 1)
            guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { continue }

            var uv = CGPoint(x: CGFloat(nx), y: CGFloat(ny)).applying(kf.displayTransform.inverted())
            if uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1 {
                uv = CGPoint(x: CGFloat(nx), y: CGFloat(ny))
            }
            guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { continue }

            let rgb = rgbAt(u: Float(uv.x), v: Float(uv.y), kf: kf)
            let facing = max(0.05, abs(simd_dot(normal, toCam / dist)))
            let score = facing * (2.8 / max(dist, 0.2))
            if score > bestScore {
                bestScore = score
                best = rgb
            }
            if bestScore > 4.5 { break }
        }
        return best
    }

    private static func solidMeshNode(positions: [Float], color: (UInt8, UInt8, UInt8)) -> SCNNode? {
        let vCount = positions.count / 3
        guard vCount >= 3, vCount % 3 == 0 else { return nil }

        let posData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let source = SCNGeometrySource(
            data: posData, semantic: .vertex, vectorCount: vCount,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )

        var indices = [UInt32](repeating: 0, count: vCount)
        for i in 0..<vCount { indices[i] = UInt32(i) }
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: vCount / 3, bytesPerIndex: 4
        )

        let geom = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = true
        mat.fillMode = .fill
        mat.diffuse.contents = UIColor(
            red: CGFloat(color.0) / 255,
            green: CGFloat(color.1) / 255,
            blue: CGFloat(color.2) / 255,
            alpha: 1
        )
        geom.materials = [mat]
        return SCNNode(geometry: geom)
    }

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

    private static func quantize(_ rgb: (UInt8, UInt8, UInt8)) -> UInt32 {
        let s = MeshDensityConfig.quantizeShift
        let r = UInt32(rgb.0 >> s)
        let g = UInt32(rgb.1 >> s)
        let b = UInt32(rgb.2 >> s)
        let bits = 8 - s
        return (r << (bits * 2)) | (g << bits) | b
    }

    private static func rgbAt(u: Float, v: Float, kf: Keyframe) -> (UInt8, UInt8, UInt8) {
        let w = kf.rgbWidth
        let h = kf.rgbHeight
        guard w > 1, h > 1, !kf.rgb.isEmpty else { return (128, 128, 128) }
        let x = min(max(Int(u * Float(w - 1)), 0), w - 1)
        let y = min(max(Int(v * Float(h - 1)), 0), h - 1)
        let o = (y * w + x) * 3
        guard o + 2 < kf.rgb.count else { return (128, 128, 128) }
        // Mild saturation
        var r = Float(kf.rgb[o]), g = Float(kf.rgb[o + 1]), b = Float(kf.rgb[o + 2])
        let gray = (r + g + b) / 3
        let sat: Float = 1.22
        r = min(max(gray + (r - gray) * sat, 0), 255)
        g = min(max(gray + (g - gray) * sat, 0), 255)
        b = min(max(gray + (b - gray) * sat, 0), 255)
        // Avoid pure white voids
        if r > 248 && g > 248 && b > 248 {
            r = 230; g = 228; b = 220
        }
        return (UInt8(r), UInt8(g), UInt8(b))
    }

    // MARK: - Capture

    static func makeKeyframe(
        from frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewport: CGSize,
        maxWidth: Int = MeshDensityConfig.keyframeMaxWidth
    ) -> Keyframe? {
        guard let (rgb, w, h) = extractRGB(buffer: frame.capturedImage, maxWidth: maxWidth) else { return nil }
        // Skip full UIImage during live scan (heavy). Tiny placeholder keeps type happy.
        let image = UIImage()
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
            image: image
        )
    }

    private static func uiImage(rgb: [UInt8], width: Int, height: Int) -> UIImage? {
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
