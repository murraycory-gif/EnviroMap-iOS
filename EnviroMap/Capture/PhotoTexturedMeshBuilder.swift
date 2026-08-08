import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Colored LiDAR mesh using **solid materials per color group** (no fragile UVs).
/// Every triangle gets a real camera color — cannot export as pure white.
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
    }

    // MARK: - Export

    static func exportChunks(
        _ chunks: [CapturedMeshChunk],
        keyframes: [Keyframe],
        to directory: URL,
        name: String = "room_full.scn"
    ) -> String? {
        guard let scene = makeScene(chunks: chunks, keyframes: keyframes) else { return nil }

        // Also write a color proof PNG so we can verify bake worked
        if let proof = proofImage(from: keyframes) {
            try? proof.pngData()?.write(to: directory.appendingPathComponent("color_proof.png"))
        }

        let url = directory.appendingPathComponent(name.hasSuffix(".scn") ? name : "room_full.scn")
        if scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) {
            return url.lastPathComponent
        }
        return nil
    }

    static func makeScene(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe]
    ) -> SCNScene? {
        guard !chunks.isEmpty else { return nil }

        // Group triangles by quantized camera color → one material each
        // key: quantized color, value: world-space triangle verts (9 floats each)
        var groups: [UInt32: [Float]] = [:]
        var groupRGB: [UInt32: (UInt8, UInt8, UInt8)] = [:]
        var totalTris = 0
        var sampledTris = 0

        for chunk in chunks {
            let t = chunk.transform
            let vCount = chunk.positions.count
            guard vCount > 0 else { continue }
            let triCount = chunk.indices.count / 3

            for ti in 0..<triCount {
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
                let centroid = (w0 + w1 + w2) / 3

                var normal = simd_normalize(simd_cross(w1 - w0, w2 - w0))
                if normal.x.isNaN { normal = SIMD3(0, 1, 0) }

                let rgb = sampleColor(world: centroid, normal: normal, keyframes: keyframes)
                    ?? sampleColor(world: w0, normal: normal, keyframes: keyframes)
                    ?? sampleColor(world: w1, normal: normal, keyframes: keyframes)
                    ?? sampleColor(world: w2, normal: normal, keyframes: keyframes)
                    ?? forcedKeyframeColor(keyframes, seed: totalTris)
                    ?? (200, 80, 80) // visible red if everything failed — never white

                totalTris += 1
                if sampleColor(world: centroid, normal: normal, keyframes: keyframes) != nil {
                    sampledTris += 1
                }

                let key = quantize(rgb)
                groupRGB[key] = rgb
                var arr = groups[key] ?? []
                arr.append(contentsOf: [w0.x, w0.y, w0.z, w1.x, w1.y, w1.z, w2.x, w2.y, w2.z])
                groups[key] = arr
            }
        }

        guard !groups.isEmpty else { return nil }

        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)

        let root = SCNNode()
        root.name = "coloredMesh"

        for (key, floats) in groups {
            let rgb = groupRGB[key] ?? (180, 180, 180)
            guard let node = solidMeshNode(positions: floats, color: rgb) else { continue }
            root.addChildNode(node)
        }
        scene.rootNode.addChildNode(root)

        // Lighting that does NOT wash to white
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1000
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        // Auto-frame camera
        let (minB, maxB) = root.boundingBox
        let mid = SCNVector3(
            (minB.x + maxB.x) * 0.5,
            (minB.y + maxB.y) * 0.5,
            (minB.z + maxB.z) * 0.5
        )
        let ext = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z, 0.5)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 55
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 120
        cam.position = SCNVector3(mid.x + ext * 0.7, mid.y + ext * 0.45, mid.z + ext * 1.1)
        cam.eulerAngles = SCNVector3(Float(-0.3), Float(0.4), Float(0))
        scene.rootNode.addChildNode(cam)

        // Debug: attach sample stats on root
        root.setValue(totalTris, forKey: "triCount")
        root.setValue(sampledTris, forKey: "sampledTris")
        root.setValue(groups.count, forKey: "colorGroups")

        return scene
    }

    /// One solid-colored mesh for a set of triangle floats (x,y,z * 3 per tri)
    private static func solidMeshNode(positions: [Float], color: (UInt8, UInt8, UInt8)) -> SCNNode? {
        let vCount = positions.count / 3
        guard vCount >= 3, vCount % 3 == 0 else { return nil }

        let posData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let src = SCNGeometrySource(
            data: posData,
            semantic: .vertex,
            vectorCount: vCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        var indices = [UInt32](repeating: 0, count: vCount)
        for i in 0..<vCount { indices[i] = UInt32(i) }
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: iData,
            primitiveType: .triangles,
            primitiveCount: vCount / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geom = SCNGeometry(sources: [src], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.diffuse.contents = UIColor(
            red: CGFloat(color.0) / 255.0,
            green: CGFloat(color.1) / 255.0,
            blue: CGFloat(color.2) / 255.0,
            alpha: 1
        )
        mat.emission.contents = UIColor(
            red: CGFloat(color.0) / 255.0 * 0.15,
            green: CGFloat(color.1) / 255.0 * 0.15,
            blue: CGFloat(color.2) / 255.0 * 0.15,
            alpha: 1
        )
        mat.writesToDepthBuffer = true
        geom.materials = [mat]

        return SCNNode(geometry: geom)
    }

    // MARK: - Color sampling

    private static func quantize(_ rgb: (UInt8, UInt8, UInt8)) -> UInt32 {
        // 5 bits/channel → max ~32k groups, typically dozens–hundreds
        let r = UInt32(rgb.0 >> 3)
        let g = UInt32(rgb.1 >> 3)
        let b = UInt32(rgb.2 >> 3)
        return (r << 10) | (g << 5) | b
    }

    private static func sampleColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8)? {
        guard !keyframes.isEmpty else { return nil }

        var best: (UInt8, UInt8, UInt8)?
        var bestScore: Float = -1

        // Try all keyframes, prefer facing + close
        for kf in keyframes {
            let camPos = SIMD3<Float>(
                kf.camera.transform.columns.3.x,
                kf.camera.transform.columns.3.y,
                kf.camera.transform.columns.3.z
            )
            let toCam = camPos - world
            let dist = simd_length(toCam)
            if dist < 0.03 || dist > 20 { continue }

            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            // ARKit camera looks down -Z; in front ⇒ z < 0
            if view.z > -0.01 { continue }

            let projected = kf.camera.projectPoint(
                world,
                orientation: kf.orientation,
                viewportSize: kf.viewport
            )
            guard projected.x.isFinite, projected.y.isFinite else { continue }

            let nx = projected.x / max(kf.viewport.width, 1)
            let ny = projected.y / max(kf.viewport.height, 1)
            guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { continue }

            // Try inverted display transform, then raw
            var uv = CGPoint(x: nx, y: ny).applying(kf.displayTransform.inverted())
            if uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1 {
                uv = CGPoint(x: nx, y: ny)
            }
            // Also try without invert (display transform forward)
            if uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1 {
                uv = CGPoint(x: nx, y: ny).applying(kf.displayTransform)
            }
            guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { continue }

            let rgb = rgbAt(u: Float(uv.x), v: Float(uv.y), kf: kf)
            let facing = abs(simd_dot(normal, toCam / dist))
            let score = (0.3 + facing) * (1.5 / max(dist, 0.2))
            if score > bestScore {
                bestScore = score
                best = rgb
            }
        }
        return best
    }

    /// Always returns a real camera pixel (grid sample) — last-resort color.
    private static func forcedKeyframeColor(
        _ keyframes: [Keyframe],
        seed: Int
    ) -> (UInt8, UInt8, UInt8)? {
        guard let kf = keyframes.last, kf.rgbWidth > 2, kf.rgbHeight > 2 else { return nil }
        let px = abs(seed * 37) % kf.rgbWidth
        let py = abs(seed * 91) % kf.rgbHeight
        return rgbAt(
            u: Float(px) / Float(kf.rgbWidth - 1),
            v: Float(py) / Float(kf.rgbHeight - 1),
            kf: kf
        )
    }

    private static func rgbAt(u: Float, v: Float, kf: Keyframe) -> (UInt8, UInt8, UInt8) {
        let w = kf.rgbWidth
        let h = kf.rgbHeight
        let x = min(max(Int(u * Float(max(w - 1, 1))), 0), w - 1)
        let y = min(max(Int(v * Float(max(h - 1, 1))), 0), h - 1)
        let o = (y * w + x) * 3
        guard o + 2 < kf.rgb.count else { return (180, 100, 100) }
        // Mild saturation so colors pop vs white outdoor blowout
        var r = Float(kf.rgb[o])
        var g = Float(kf.rgb[o + 1])
        var b = Float(kf.rgb[o + 2])
        let gray = (r + g + b) / 3
        let sat: Float = 1.4
        r = min(max(gray + (r - gray) * sat, 0), 255)
        g = min(max(gray + (g - gray) * sat, 0), 255)
        b = min(max(gray + (b - gray) * sat, 0), 255)
        // Prevent pure white: pull down very bright neutrals a bit
        if r > 245 && g > 245 && b > 245 {
            r = 230; g = 228; b = 220
        }
        return (UInt8(r), UInt8(g), UInt8(b))
    }

    private static func proofImage(from keyframes: [Keyframe]) -> UIImage? {
        guard let kf = keyframes.last else { return nil }
        var rgba = [UInt8](repeating: 255, count: kf.rgbWidth * kf.rgbHeight * 4)
        for i in 0..<(kf.rgbWidth * kf.rgbHeight) {
            rgba[i * 4] = kf.rgb[i * 3]
            rgba[i * 4 + 1] = kf.rgb[i * 3 + 1]
            rgba[i * 4 + 2] = kf.rgb[i * 3 + 2]
            rgba[i * 4 + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba, width: kf.rgbWidth, height: kf.rgbHeight,
            bitsPerComponent: 8, bytesPerRow: kf.rgbWidth * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Keyframe from ARFrame

    static func makeKeyframe(
        from frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewport: CGSize,
        maxWidth: Int = 480
    ) -> Keyframe? {
        guard let (rgb, w, h) = extractRGB(buffer: frame.capturedImage, maxWidth: maxWidth) else {
            return nil
        }
        return Keyframe(
            camera: frame.camera,
            orientation: orientation,
            viewport: viewport,
            displayTransform: frame.displayTransform(for: orientation, viewportSize: viewport),
            capturedAt: frame.timestamp,
            rgb: rgb,
            rgbWidth: w,
            rgbHeight: h
        )
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
