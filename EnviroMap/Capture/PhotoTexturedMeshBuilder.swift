import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Dense LiDAR mesh + real camera photo textures (per-chunk best-view bake).
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
        /// Cached UIImage for material diffuse
        let image: UIImage
    }

    // MARK: - Export

    static func exportChunks(
        _ chunks: [CapturedMeshChunk],
        keyframes: [Keyframe],
        to directory: URL,
        name: String = "room_full.scn"
    ) -> String? {
        guard let scene = makeScene(chunks: chunks, keyframes: keyframes) else { return nil }
        let scnName = name.hasSuffix(".scn") ? name : "room_full.scn"
        let scnURL = directory.appendingPathComponent(scnName)
        if scene.write(to: scnURL, options: nil, delegate: nil, progressHandler: nil) {
            return scnName
        }
        return nil
    }

    static func makeScene(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe]
    ) -> SCNScene? {
        guard !chunks.isEmpty else { return nil }

        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.93, green: 0.94, blue: 0.97, alpha: 1)

        var any = false
        for chunk in chunks {
            if let node = makeTexturedNode(chunk: chunk, keyframes: keyframes) {
                scene.rootNode.addChildNode(node)
                any = true
            }
        }
        guard any else { return nil }

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1200
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 60
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 80
        cam.position = SCNVector3(Float(2.0), Float(1.5), Float(2.8))
        cam.eulerAngles = SCNVector3(Float(-0.28), Float(0.5), Float(0))
        scene.rootNode.addChildNode(cam)

        return scene
    }

    // MARK: - Photo-textured node (real colors)

    private static func makeTexturedNode(
        chunk: CapturedMeshChunk,
        keyframes: [Keyframe]
    ) -> SCNNode? {
        let vCount = chunk.positions.count
        guard vCount > 0, chunk.indices.count >= 3, !keyframes.isEmpty else { return nil }

        let transform = chunk.transform

        // Chunk center in world space
        var center = SIMD3<Float>(0, 0, 0)
        for p in chunk.positions {
            let w = transform * SIMD4<Float>(p.x, p.y, p.z, 1)
            center += SIMD3<Float>(w.x, w.y, w.z)
        }
        center /= Float(vCount)

        // Average normal
        var avgN = SIMD3<Float>(0, 1, 0)
        if !chunk.normals.isEmpty {
            avgN = .zero
            for n in chunk.normals {
                let wn = transform * SIMD4<Float>(n.x, n.y, n.z, 0)
                avgN += SIMD3<Float>(wn.x, wn.y, wn.z)
            }
            avgN = simd_normalize(avgN)
        }

        guard let bestKF = bestKeyframe(for: center, normal: avgN, keyframes: keyframes) else {
            return solidColorNode(chunk: chunk, color: UIColor(white: 0.7, alpha: 1))
        }

        // Build positions + UVs projected into best keyframe photo
        var positions = [Float](repeating: 0, count: vCount * 3)
        var normals = [Float](repeating: 0, count: vCount * 3)
        var uvs = [Float](repeating: 0.5, count: vCount * 2)
        var colorBytes = [UInt8](repeating: 180, count: vCount * 4)

        var uvHits = 0
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

            if let (u, v, r, g, b) = projectSample(world: world, kf: bestKF) {
                uvs[i * 2] = u
                uvs[i * 2 + 1] = 1.0 - v // flip V for SceneKit
                colorBytes[i * 4] = r
                colorBytes[i * 4 + 1] = g
                colorBytes[i * 4 + 2] = b
                colorBytes[i * 4 + 3] = 255
                uvHits += 1
            } else if let (r, g, b) = sampleNearestRGB(world: world, keyframes: keyframes) {
                colorBytes[i * 4] = r
                colorBytes[i * 4 + 1] = g
                colorBytes[i * 4 + 2] = b
                colorBytes[i * 4 + 3] = 255
            }
        }

        let posData = floatData(positions)
        let nrmData = floatData(normals)
        let uvData = floatData(uvs)
        let colData = colorBytes.withUnsafeBufferPointer { Data(buffer: $0) }

        let sources: [SCNGeometrySource] = [
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
            SCNGeometrySource(
                data: uvData, semantic: .texcoord, vectorCount: vCount,
                usesFloatComponents: true, componentsPerVector: 2,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 8
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
            primitiveCount: primCount, bytesPerIndex: 4
        )

        let geom = SCNGeometry(sources: sources, elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = true

        // Photo texture when UVs landed; else solid average vertex color
        if uvHits > vCount / 10 {
            mat.diffuse.contents = bestKF.image
            mat.diffuse.wrapS = .clamp
            mat.diffuse.wrapT = .clamp
            mat.diffuse.magnificationFilter = .linear
            mat.diffuse.minificationFilter = .linear
        } else {
            mat.diffuse.contents = averageUIColor(colorBytes: colorBytes, count: vCount)
        }

        geom.materials = [mat]
        let node = SCNNode(geometry: geom)
        node.simdTransform = transform
        return node
    }

    private static func solidColorNode(chunk: CapturedMeshChunk, color: UIColor) -> SCNNode? {
        let vCount = chunk.positions.count
        guard vCount > 0 else { return nil }
        var positions = [Float](repeating: 0, count: vCount * 3)
        for i in 0..<vCount {
            positions[i * 3] = chunk.positions[i].x
            positions[i * 3 + 1] = chunk.positions[i].y
            positions[i * 3 + 2] = chunk.positions[i].z
        }
        let posData = floatData(positions)
        let src = SCNGeometrySource(
            data: posData, semantic: .vertex, vectorCount: vCount,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        var idx = chunk.indices
        let prim = idx.count / 3
        guard prim > 0 else { return nil }
        let iData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let el = SCNGeometryElement(data: iData, primitiveType: .triangles, primitiveCount: prim, bytesPerIndex: 4)
        let geom = SCNGeometry(sources: [src], elements: [el])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.diffuse.contents = color
        geom.materials = [mat]
        let n = SCNNode(geometry: geom)
        n.simdTransform = chunk.transform
        return n
    }

    // MARK: - Projection / sampling

    private static func bestKeyframe(
        for world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> Keyframe? {
        var best: Keyframe?
        var bestScore: Float = -1
        for kf in keyframes {
            let camPos = SIMD3<Float>(
                kf.camera.transform.columns.3.x,
                kf.camera.transform.columns.3.y,
                kf.camera.transform.columns.3.z
            )
            let toCam = camPos - world
            let dist = simd_length(toCam)
            if dist < 0.05 || dist > 12 { continue }
            let facing = simd_dot(normal, toCam / dist)
            if facing < 0.0 { continue }
            let score = facing * (2.0 / max(dist, 0.3))
            if score > bestScore {
                bestScore = score
                best = kf
            }
        }
        // Fallback: nearest keyframe by distance
        if best == nil {
            best = keyframes.min(by: {
                let a = SIMD3<Float>($0.camera.transform.columns.3.x, $0.camera.transform.columns.3.y, $0.camera.transform.columns.3.z)
                let b = SIMD3<Float>($1.camera.transform.columns.3.x, $1.camera.transform.columns.3.y, $1.camera.transform.columns.3.z)
                return simd_distance(a, world) < simd_distance(b, world)
            })
        }
        return best
    }

    /// Returns u,v in 0…1 plus RGB sample
    private static func projectSample(
        world: SIMD3<Float>,
        kf: Keyframe
    ) -> (Float, Float, UInt8, UInt8, UInt8)? {
        let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
        if view.z >= 0 { return nil }

        let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
        if !projected.x.isFinite || !projected.y.isFinite { return nil }

        let nx = projected.x / max(kf.viewport.width, 1)
        let ny = projected.y / max(kf.viewport.height, 1)
        if nx < 0 || nx > 1 || ny < 0 || ny > 1 { return nil }

        // View normalized → image UV
        let img = CGPoint(x: nx, y: ny).applying(kf.displayTransform.inverted())
        var u = Float(img.x)
        var v = Float(img.y)

        // If outside, try raw nx,ny (some devices)
        if u < 0 || u > 1 || v < 0 || v > 1 {
            u = Float(nx)
            v = Float(ny)
        }
        if u < 0 || u > 1 || v < 0 || v > 1 { return nil }

        let (r, g, b) = rgbAt(u: u, v: v, kf: kf)
        return (u, v, r, g, b)
    }

    private static func sampleNearestRGB(
        world: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8)? {
        for kf in keyframes.reversed() {
            if let s = projectSample(world: world, kf: kf) {
                return (s.2, s.3, s.4)
            }
        }
        // Last resort: center pixel of latest keyframe (always real camera color)
        if let kf = keyframes.last {
            return rgbAt(u: 0.5, v: 0.5, kf: kf)
        }
        return nil
    }

    private static func rgbAt(u: Float, v: Float, kf: Keyframe) -> (UInt8, UInt8, UInt8) {
        let w = kf.rgbWidth
        let h = kf.rgbHeight
        guard w > 0, h > 0, !kf.rgb.isEmpty else { return (200, 200, 200) }
        let x = min(max(Int(u * Float(w - 1)), 0), w - 1)
        let y = min(max(Int(v * Float(h - 1)), 0), h - 1)
        let i = (y * w + x) * 3
        guard i + 2 < kf.rgb.count else { return (200, 200, 200) }
        return (kf.rgb[i], kf.rgb[i + 1], kf.rgb[i + 2])
    }

    private static func averageUIColor(colorBytes: [UInt8], count: Int) -> UIColor {
        guard count > 0 else { return UIColor(white: 0.7, alpha: 1) }
        var r = 0, g = 0, b = 0
        for i in 0..<count {
            r += Int(colorBytes[i * 4])
            g += Int(colorBytes[i * 4 + 1])
            b += Int(colorBytes[i * 4 + 2])
        }
        return UIColor(
            red: CGFloat(r) / CGFloat(count) / 255,
            green: CGFloat(g) / CGFloat(count) / 255,
            blue: CGFloat(b) / CGFloat(count) / 255,
            alpha: 1
        )
    }

    private static func floatData(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: - Keyframe from ARFrame

    static func makeKeyframe(
        from frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewport: CGSize,
        maxWidth: Int = 480
    ) -> Keyframe? {
        let buffer = frame.capturedImage
        guard let (rgb, w, h) = extractRGB(buffer: buffer, maxWidth: maxWidth) else { return nil }
        guard let image = uiImage(rgb: rgb, width: w, height: h) else { return nil }
        let display = frame.displayTransform(for: orientation, viewportSize: viewport)
        return Keyframe(
            camera: frame.camera,
            orientation: orientation,
            viewport: viewport,
            displayTransform: display,
            capturedAt: frame.timestamp,
            rgb: rgb,
            rgbWidth: w,
            rgbHeight: h,
            image: image
        )
    }

    private static func uiImage(rgb: [UInt8], width: Int, height: Int) -> UIImage? {
        // RGB → RGBA CGImage
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = rgb[i * 3]
            rgba[i * 4 + 1] = rgb[i * 3 + 1]
            rgba[i * 4 + 2] = rgb[i * 3 + 2]
            rgba[i * 4 + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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
