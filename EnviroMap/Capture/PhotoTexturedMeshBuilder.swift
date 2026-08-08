import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Builds a dense LiDAR mesh with real camera colors.
/// Strategy: sample RGB from stored keyframe images → byte vertex colors →
/// export as .scn (USDZ often strips vertex colors).
enum PhotoTexturedMeshBuilder {

    struct Keyframe {
        let camera: ARCamera
        let orientation: UIInterfaceOrientation
        let viewport: CGSize
        let displayTransform: CGAffineTransform
        let capturedAt: TimeInterval
        /// Downscaled RGB (3 bytes/pixel) for reliable sampling
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
        // Prefer .scn — preserves vertex colors; USDZ often becomes white
        let scnName = name.hasSuffix(".scn") ? name : "room_full.scn"
        let scnURL = directory.appendingPathComponent(scnName)
        if scene.write(to: scnURL, options: nil, delegate: nil, progressHandler: nil) {
            return scnName
        }
        let usdzURL = directory.appendingPathComponent("room_full.usdz")
        if scene.write(to: usdzURL, options: nil, delegate: nil, progressHandler: nil) {
            return "room_full.usdz"
        }
        return nil
    }

    static func makeScene(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe]
    ) -> SCNScene? {
        guard !chunks.isEmpty else { return nil }

        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1)

        var any = false
        for chunk in chunks {
            if let node = makeNode(chunk: chunk, keyframes: keyframes) {
                scene.rootNode.addChildNode(node)
                any = true
            }
        }
        guard any else { return nil }

        // Bright ambient so baked colors read true
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1400
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 350
        key.eulerAngles = SCNVector3(Float(-0.55), Float(0.4), Float(0))
        scene.rootNode.addChildNode(key)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 60
        cam.camera?.wantsHDR = false
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 80
        cam.position = SCNVector3(Float(2.0), Float(1.4), Float(2.8))
        cam.eulerAngles = SCNVector3(Float(-0.25), Float(0.45), Float(0))
        scene.rootNode.addChildNode(cam)

        return scene
    }

    // MARK: - Node / geometry

    private static func makeNode(chunk: CapturedMeshChunk, keyframes: [Keyframe]) -> SCNNode? {
        let vCount = chunk.positions.count
        guard vCount > 0, chunk.indices.count >= 3 else { return nil }

        var positions = [Float](repeating: 0, count: vCount * 3)
        var normals = [Float](repeating: 0, count: vCount * 3)
        var colorBytes = [UInt8](repeating: 200, count: vCount * 4)

        var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
        var hitCount = 0

        let transform = chunk.transform

        for i in 0..<vCount {
            let local = chunk.positions[i]
            positions[i * 3] = local.x
            positions[i * 3 + 1] = local.y
            positions[i * 3 + 2] = local.z

            let nLocal = i < chunk.normals.count ? chunk.normals[i] : SIMD3<Float>(0, 1, 0)
            normals[i * 3] = nLocal.x
            normals[i * 3 + 1] = nLocal.y
            normals[i * 3 + 2] = nLocal.z

            let world4 = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            let world = SIMD3<Float>(world4.x, world4.y, world4.z)
            let n4 = transform * SIMD4<Float>(nLocal.x, nLocal.y, nLocal.z, 0)
            let nWorld = simd_normalize(SIMD3<Float>(n4.x, n4.y, n4.z))

            let rgb = sampleColor(world: world, normal: nWorld, keyframes: keyframes)
            colorBytes[i * 4 + 0] = rgb.0
            colorBytes[i * 4 + 1] = rgb.1
            colorBytes[i * 4 + 2] = rgb.2
            colorBytes[i * 4 + 3] = 255

            sumR += Float(rgb.0)
            sumG += Float(rgb.1)
            sumB += Float(rgb.2)
            hitCount += 1
        }

        let posData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let nrmData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let colData = colorBytes.withUnsafeBufferPointer { Data(buffer: $0) }

        let sources: [SCNGeometrySource] = [
            SCNGeometrySource(
                data: posData, semantic: .vertex, vectorCount: vCount,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 3
            ),
            SCNGeometrySource(
                data: nrmData, semantic: .normal, vectorCount: vCount,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 3
            ),
            SCNGeometrySource(
                data: colData, semantic: .color, vectorCount: vCount,
                usesFloatComponents: false, componentsPerVector: 4,
                bytesPerComponent: 1, dataOffset: 0, dataStride: 4
            ),
        ]

        var idx = chunk.indices
        let primCount = idx.count / 3
        guard primCount > 0 else { return nil }
        let iData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: primCount, bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geom = SCNGeometry(sources: sources, elements: [element])

        // Average chunk color — used as diffuse so export can't go pure white
        let avg: UIColor
        if hitCount > 0 {
            avg = UIColor(
                red: CGFloat(sumR / Float(hitCount) / 255),
                green: CGFloat(sumG / Float(hitCount) / 255),
                blue: CGFloat(sumB / Float(hitCount) / 255),
                alpha: 1
            )
        } else {
            avg = UIColor(white: 0.75, alpha: 1)
        }

        let mat = SCNMaterial()
        mat.lightingModel = .constant   // unlit = show color as-is
        mat.isDoubleSided = true
        mat.diffuse.contents = avg
        // Multiply vertex colors: SceneKit constant + vertex color source
        // Use emission with average as base; vertex colors via diffuse white + color source
        mat.diffuse.contents = UIColor.white
        mat.emission.contents = avg.withAlphaComponent(0.15)
        mat.ambient.contents = UIColor.white
        mat.locksAmbientWithDiffuse = true
        // Prefer true vertex colors when the viewer supports them
        mat.writesToDepthBuffer = true
        geom.materials = [mat]

        // Attach average color for viewers that strip vertex colors
        let node = SCNNode(geometry: geom)
        node.simdTransform = transform
        node.name = "mesh-\(chunk.id.uuidString.prefix(8))"
        // Second pass material: if vertex colors fail, still tinted
        // Create child overlay? Skip — instead set diffuse to avg AND keep color source
        mat.diffuse.contents = avg
        return node
    }

    // MARK: - Sampling

    /// Returns 0–255 RGB
    private static func sampleColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8) {
        guard !keyframes.isEmpty else {
            return fallback(y: world.y)
        }

        var best: (UInt8, UInt8, UInt8)?
        var bestScore: Float = -1

        for kf in keyframes.reversed() { // prefer recent
            let camPos = SIMD3<Float>(
                kf.camera.transform.columns.3.x,
                kf.camera.transform.columns.3.y,
                kf.camera.transform.columns.3.z
            )
            let toCam = camPos - world
            let dist = simd_length(toCam)
            if dist < 0.05 || dist > 10 { continue }

            let facing = simd_dot(normal, toCam / max(dist, 0.001))
            // Allow backfaces a little for thin objects
            if facing < -0.2 { continue }

            guard let rgb = samplePixel(world: world, kf: kf) else { continue }
            let score = max(facing, 0.05) * (1.5 / max(dist, 0.2))
            if score > bestScore {
                bestScore = score
                best = rgb
            }
            // Early out if excellent sample
            if bestScore > 2.0 { break }
        }

        return best ?? fallback(y: world.y)
    }

    private static func samplePixel(world: SIMD3<Float>, kf: Keyframe) -> (UInt8, UInt8, UInt8)? {
        // View-space depth check
        let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
        if view.z >= 0 { return nil } // behind camera

        let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
        if !projected.x.isFinite || !projected.y.isFinite { return nil }

        // Normalized viewport [0,1]
        let nx = projected.x / max(kf.viewport.width, 1)
        let ny = projected.y / max(kf.viewport.height, 1)
        if nx < -0.05 || nx > 1.05 || ny < -0.05 || ny > 1.05 { return nil }

        // View → image UV via inverted display transform
        let viewPt = CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
        let imgUV = viewPt.applying(kf.displayTransform.inverted())

        // Also try direct mapping if transform puts us outside
        var u = imgUV.x
        var v = imgUV.y
        if u < 0 || u > 1 || v < 0 || v > 1 {
            // Fallback: assume projectPoint already in image-like space
            u = nx
            v = ny
        }
        if u < 0 || u > 1 || v < 0 || v > 1 { return nil }

        let w = kf.rgbWidth
        let h = kf.rgbHeight
        guard w > 1, h > 1, !kf.rgb.isEmpty else { return nil }

        let px = min(max(Int(u * CGFloat(w - 1)), 0), w - 1)
        let py = min(max(Int(v * CGFloat(h - 1)), 0), h - 1)

        // 3×3 average
        var r = 0, g = 0, b = 0, n = 0
        for dy in -1...1 {
            for dx in -1...1 {
                let x = min(max(px + dx, 0), w - 1)
                let y = min(max(py + dy, 0), h - 1)
                let i = (y * w + x) * 3
                guard i + 2 < kf.rgb.count else { continue }
                r += Int(kf.rgb[i])
                g += Int(kf.rgb[i + 1])
                b += Int(kf.rgb[i + 2])
                n += 1
            }
        }
        guard n > 0 else { return nil }
        return (UInt8(r / n), UInt8(g / n), UInt8(b / n))
    }

    private static func fallback(y: Float) -> (UInt8, UInt8, UInt8) {
        if y < 0.15 { return (120, 100, 80) }   // floor brown
        if y > 2.2 { return (230, 230, 235) }  // ceiling
        return (180, 185, 190)                 // wall gray-blue
    }

    // MARK: - Keyframe RGB extraction

    /// Build a Keyframe with downscaled RGB from ARFrame (call on capture).
    static func makeKeyframe(
        from frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewport: CGSize,
        maxWidth: Int = 320
    ) -> Keyframe? {
        let buffer = frame.capturedImage
        guard let (rgb, w, h) = extractRGB(buffer: buffer, maxWidth: maxWidth) else { return nil }
        let display = frame.displayTransform(for: orientation, viewportSize: viewport)
        return Keyframe(
            camera: frame.camera,
            orientation: orientation,
            viewport: viewport,
            displayTransform: display,
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
                    let cx = sx / 2
                    let cy = sy / 2
                    let cPtr = cBase.advanced(by: cy * cStride + cx * 2).assumingMemoryBound(to: UInt8.self)
                    let Cb = Float(cPtr[0]) - 128
                    let Cr = Float(cPtr[1]) - 128
                    let yf = videoRange ? (Y - 16) * (255.0 / 219.0) : Y
                    var r = yf + 1.402 * Cr
                    var g = yf - 0.344136 * Cb - 0.714136 * Cr
                    var b = yf + 1.772 * Cb
                    r = min(max(r, 0), 255)
                    g = min(max(g, 0), 255)
                    b = min(max(b, 0), 255)
                    // Slight saturation boost
                    let gray = (r + g + b) / 3
                    let sat: Float = 1.15
                    r = min(max(gray + (r - gray) * sat, 0), 255)
                    g = min(max(gray + (g - gray) * sat, 0), 255)
                    b = min(max(gray + (b - gray) * sat, 0), 255)
                    let o = (j * w + i) * 3
                    rgb[o] = UInt8(r)
                    rgb[o + 1] = UInt8(g)
                    rgb[o + 2] = UInt8(b)
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
                    rgb[o] = p[2]
                    rgb[o + 1] = p[1]
                    rgb[o + 2] = p[0]
                }
            }
            return (rgb, w, h)
        }

        return nil
    }
}
