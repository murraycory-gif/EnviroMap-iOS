import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Dense multi-view colored mesh (3D Snap–style photo colors on LiDAR geometry).
/// Per-triangle colors from the best camera frames — not one texture per giant chunk.
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
        guard !chunks.isEmpty, !keyframes.isEmpty else { return nil }

        let kfs = selectKeyframes(keyframes, limit: 56)
        guard !kfs.isEmpty else { return nil }

        struct Tri {
            let w0, w1, w2: SIMD3<Float>
            let normal: SIMD3<Float>
        }

        var tris: [Tri] = []
        var est = 0
        for c in chunks { est += c.indices.count / 3 }
        // Keep dense geometry (cars need it)
        tris.reserveCapacity(min(est, 350_000))

        for chunk in chunks {
            let t = chunk.transform
            let vCount = chunk.positions.count
            guard vCount > 0 else { continue }
            let triCount = chunk.indices.count / 3
            // Almost never skip triangles — objects disappear when we do
            let step = triCount > 180_000 ? 2 : 1

            for ti in stride(from: 0, to: triCount, by: step) {
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
                if n.x.isNaN { n = SIMD3(0, 1, 0) }
                tris.append(Tri(w0: w0, w1: w1, w2: w2, normal: n))
            }
        }
        guard !tris.isEmpty else { return nil }

        let triCount = tris.count
        var colors = [(UInt8, UInt8, UInt8)](repeating: (160, 160, 160), count: triCount)

        // Multi-view color per triangle (this is what makes a blue car look blue)
        DispatchQueue.concurrentPerform(iterations: triCount) { i in
            let tri = tris[i]
            colors[i] = colorForTriangle(tri.w0, tri.w1, tri.w2, normal: tri.normal, keyframes: kfs)
        }

        // Finer quantize = more color detail (6 bits/channel)
        var groups: [UInt32: [Float]] = [:]
        var groupRGB: [UInt32: (UInt8, UInt8, UInt8)] = [:]
        groups.reserveCapacity(min(triCount / 2, 12_000))

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
        scene.background.contents = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)

        let root = SCNNode()
        root.name = "coloredMesh"

        for (key, floats) in groups {
            let rgb = groupRGB[key] ?? (160, 160, 160)
            if let node = solidMeshNode(positions: floats, color: rgb) {
                root.addChildNode(node)
            }
        }
        scene.rootNode.addChildNode(root)

        // Lighting: show shape without washing out car paint colors
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 900
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 350
        key.eulerAngles = SCNVector3(Float(-0.55), Float(0.4), Float(0))
        scene.rootNode.addChildNode(key)

        let (minB, maxB) = root.boundingBox
        let mid = SCNVector3(
            (minB.x + maxB.x) * 0.5,
            (minB.y + maxB.y) * 0.5,
            (minB.z + maxB.z) * 0.5
        )
        let ext = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z, 0.4)
        let cam = SCNNode()
        cam.name = "previewCam"
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 50
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 200
        cam.position = SCNVector3(mid.x + ext * 0.5, mid.y + ext * 0.35, mid.z + ext * 1.0)
        cam.eulerAngles = SCNVector3(Float(-0.25), Float(0.35), Float(0))
        scene.rootNode.addChildNode(cam)

        return scene
    }

    // MARK: - Color (multi-view)

    private static func colorForTriangle(
        _ w0: SIMD3<Float>,
        _ w1: SIMD3<Float>,
        _ w2: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8) {
        let centroid = (w0 + w1 + w2) / 3
        // Sample several points so paint / labels on a car survive
        let points = [
            centroid,
            w0, w1, w2,
            (w0 + w1) * 0.5,
            (w1 + w2) * 0.5,
            (w2 + w0) * 0.5
        ]

        var rSum = 0, gSum = 0, bSum = 0, n = 0
        for p in points {
            if let c = sampleBestColor(world: p, normal: normal, keyframes: keyframes) {
                rSum += Int(c.0); gSum += Int(c.1); bSum += Int(c.2)
                n += 1
            }
        }
        if n > 0 {
            return (UInt8(rSum / n), UInt8(gSum / n), UInt8(bSum / n))
        }
        // Last-resort: pick any visible keyframe pixel near center
        return forcedKeyframeColor(keyframes) ?? (40, 80, 140) // cool fallback, not beige
    }

    private static func sampleBestColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8)? {
        var best: (UInt8, UInt8, UInt8)?
        var bestScore: Float = -1

        // Prefer recent frames (more of the object usually)
        for kf in keyframes.reversed() {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            // Cars are often scanned 1–4 m away
            if dist < 0.08 || dist > 14 { continue }

            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.03 { continue }

            let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
            guard projected.x.isFinite, projected.y.isFinite else { continue }

            let nx = projected.x / max(kf.viewport.width, 1)
            let ny = projected.y / max(kf.viewport.height, 1)
            // Slight margin so edge of frame still counts
            guard nx >= -0.02, nx <= 1.02, ny >= -0.02, ny <= 1.02 else { continue }
            let cx = min(max(nx, 0), 1)
            let cy = min(max(ny, 0), 1)

            var uv = CGPoint(x: CGFloat(cx), y: CGFloat(cy)).applying(kf.displayTransform.inverted())
            if uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1 {
                uv = CGPoint(x: CGFloat(cx), y: CGFloat(cy))
            }
            guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { continue }

            let rgb = rgbBilinear(u: Float(uv.x), v: Float(uv.y), kf: kf)
            let facing = max(0.05, abs(simd_dot(normal, toCam / dist)))
            // Prefer closer + facing camera (sharp car paint)
            let score = facing * (3.0 / max(dist, 0.2))
            if score > bestScore {
                bestScore = score
                best = rgb
            }
            // Early exit when very good
            if bestScore > 6 { break }
        }
        return best
    }

    private static func solidMeshNode(positions: [Float], color: (UInt8, UInt8, UInt8)) -> SCNNode? {
        let vCount = positions.count / 3
        guard vCount >= 3, vCount % 3 == 0 else { return nil }

        var normals = [Float](repeating: 0, count: vCount * 3)
        for t in 0..<(vCount / 3) {
            let b = t * 9
            let p0 = SIMD3(positions[b], positions[b + 1], positions[b + 2])
            let p1 = SIMD3(positions[b + 3], positions[b + 4], positions[b + 5])
            let p2 = SIMD3(positions[b + 6], positions[b + 7], positions[b + 8])
            var n = simd_normalize(simd_cross(p1 - p0, p2 - p0))
            if n.x.isNaN { n = SIMD3(0, 1, 0) }
            for k in 0..<3 {
                normals[(t * 3 + k) * 3] = n.x
                normals[(t * 3 + k) * 3 + 1] = n.y
                normals[(t * 3 + k) * 3 + 2] = n.z
            }
        }

        let posData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let nrmData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let sources = [
            SCNGeometrySource(
                data: posData, semantic: .vertex, vectorCount: vCount,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            ),
            SCNGeometrySource(
                data: nrmData, semantic: .normal, vectorCount: vCount,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            ),
        ]

        var indices = [UInt32](repeating: 0, count: vCount)
        for i in 0..<vCount { indices[i] = UInt32(i) }
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: vCount / 3, bytesPerIndex: 4
        )

        let geom = SCNGeometry(sources: sources, elements: [element])
        let mat = SCNMaterial()
        // Constant = true camera color (no wash-out on blue paint)
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = true
        mat.diffuse.contents = UIColor(
            red: CGFloat(color.0) / 255,
            green: CGFloat(color.1) / 255,
            blue: CGFloat(color.2) / 255,
            alpha: 1
        )
        geom.materials = [mat]
        return SCNNode(geometry: geom)
    }

    // MARK: - Helpers

    private static func selectKeyframes(_ all: [Keyframe], limit: Int) -> [Keyframe] {
        guard all.count > limit else { return all }
        var result: [Keyframe] = []
        // Keep most recent (best coverage of final pose)
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

    /// 6-bit quantize — enough for blue paint vs beige wall
    private static func quantize(_ rgb: (UInt8, UInt8, UInt8)) -> UInt32 {
        let r = UInt32(rgb.0 >> 2)
        let g = UInt32(rgb.1 >> 2)
        let b = UInt32(rgb.2 >> 2)
        return (r << 12) | (g << 6) | b
    }

    private static func rgbBilinear(u: Float, v: Float, kf: Keyframe) -> (UInt8, UInt8, UInt8) {
        let w = kf.rgbWidth
        let h = kf.rgbHeight
        guard w > 1, h > 1, !kf.rgb.isEmpty else { return (120, 120, 120) }

        let fx = u * Float(w - 1)
        let fy = v * Float(h - 1)
        let x0 = min(max(Int(fx), 0), w - 1)
        let y0 = min(max(Int(fy), 0), h - 1)
        let x1 = min(x0 + 1, w - 1)
        let y1 = min(y0 + 1, h - 1)
        let tx = fx - Float(x0)
        let ty = fy - Float(y0)

        func sample(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let o = (y * w + x) * 3
            guard o + 2 < kf.rgb.count else { return SIMD3(120, 120, 120) }
            return SIMD3(Float(kf.rgb[o]), Float(kf.rgb[o + 1]), Float(kf.rgb[o + 2]))
        }

        let c00 = sample(x0, y0), c10 = sample(x1, y0)
        let c01 = sample(x0, y1), c11 = sample(x1, y1)
        let c0 = c00 * (1 - tx) + c10 * tx
        let c1 = c01 * (1 - tx) + c11 * tx
        var c = c0 * (1 - ty) + c1 * ty

        // Mild saturation boost so blue cars stay blue
        let gray = (c.x + c.y + c.z) / 3
        let sat: Float = 1.18
        c = SIMD3(
            min(max(gray + (c.x - gray) * sat, 0), 255),
            min(max(gray + (c.y - gray) * sat, 0), 255),
            min(max(gray + (c.z - gray) * sat, 0), 255)
        )
        return (UInt8(c.x), UInt8(c.y), UInt8(c.z))
    }

    private static func forcedKeyframeColor(_ keyframes: [Keyframe]) -> (UInt8, UInt8, UInt8)? {
        guard let kf = keyframes.last, kf.rgbWidth > 4 else { return nil }
        return rgbBilinear(u: 0.5, v: 0.5, kf: kf)
    }

    // MARK: - Capture

    static func makeKeyframe(
        from frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewport: CGSize,
        maxWidth: Int = 640
    ) -> Keyframe? {
        guard let (rgb, w, h) = extractRGB(buffer: frame.capturedImage, maxWidth: maxWidth),
              let image = uiImage(rgb: rgb, width: w, height: h) else { return nil }
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
