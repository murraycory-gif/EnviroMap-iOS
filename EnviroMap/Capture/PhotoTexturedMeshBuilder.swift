import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Photo-textured LiDAR mesh — **one textured node per chunk** (fast + clear).
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

    // MARK: - Public

    static func makeScene(chunks: [CapturedMeshChunk], keyframes: [Keyframe]) -> SCNScene? {
        buildScene(chunks: chunks, keyframes: keyframes, textureDir: nil)
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
        guard let scene = buildScene(chunks: chunks, keyframes: keyframes, textureDir: directory) else {
            return nil
        }
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

    // MARK: - Build (chunk-level — much faster than per-triangle materials)

    private static func buildScene(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe],
        textureDir: URL?
    ) -> SCNScene? {
        guard !chunks.isEmpty, !keyframes.isEmpty else { return nil }

        let kfs = selectKeyframes(keyframes, limit: 40)
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)

        let root = SCNNode()
        root.name = "coloredMesh"

        // Build chunk nodes in parallel into a thread-safe array
        let lock = NSLock()
        var nodes: [SCNNode] = []
        nodes.reserveCapacity(chunks.count)

        DispatchQueue.concurrentPerform(iterations: chunks.count) { i in
            let chunk = chunks[i]
            if let node = makeChunkNode(chunk: chunk, keyframes: kfs, textureDir: textureDir, index: i) {
                lock.lock()
                nodes.append(node)
                lock.unlock()
            }
        }

        guard !nodes.isEmpty else { return nil }
        for n in nodes { root.addChildNode(n) }
        scene.rootNode.addChildNode(root)

        // Soft lights for form
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 750
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 450
        key.eulerAngles = SCNVector3(Float(-0.55), Float(0.4), Float(0))
        scene.rootNode.addChildNode(key)

        // Fit camera
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

    /// One photo-textured mesh piece (real camera detail).
    private static func makeChunkNode(
        chunk: CapturedMeshChunk,
        keyframes: [Keyframe],
        textureDir: URL?,
        index: Int
    ) -> SCNNode? {
        let vCount = chunk.positions.count
        guard vCount > 0, chunk.indices.count >= 3 else { return nil }

        // Cap huge chunks for speed (keep shape, thin density)
        let highDetail = UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
        let strideV: Int
        if highDetail {
            strideV = vCount > 60_000 ? 2 : 1
        } else {
            strideV = vCount > 25_000 ? 2 : 1
        }

        // Chunk center / normal for best keyframe
        var center = SIMD3<Float>(0, 0, 0)
        var avgN = SIMD3<Float>(0, 1, 0)
        var nCount = 0
        for i in stride(from: 0, to: vCount, by: max(1, vCount / 200)) {
            let p = chunk.positions[i]
            let w = chunk.transform * SIMD4<Float>(p.x, p.y, p.z, 1)
            center += SIMD3(w.x, w.y, w.z)
            nCount += 1
            if i < chunk.normals.count {
                let n = chunk.normals[i]
                let nw = chunk.transform * SIMD4<Float>(n.x, n.y, n.z, 0)
                avgN += SIMD3(nw.x, nw.y, nw.z)
            }
        }
        if nCount > 0 { center /= Float(nCount) }
        avgN = simd_normalize(avgN)

        let best = bestKeyframe(for: center, normal: avgN, keyframes: keyframes) ?? keyframes.last!

        // Build compact vertex list
        var indexMap = [Int: Int]() // old -> new
        var positions: [Float] = []
        var normals: [Float] = []
        var uvs: [Float] = []
        var colorSum = SIMD3<Float>(0, 0, 0)
        var colorN = 0
        var uvHits = 0

        positions.reserveCapacity((vCount / strideV) * 3)
        uvs.reserveCapacity((vCount / strideV) * 2)

        for i in stride(from: 0, to: vCount, by: strideV) {
            let local = chunk.positions[i]
            let world4 = chunk.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            let world = SIMD3(world4.x, world4.y, world4.z)

            let nLocal = i < chunk.normals.count ? chunk.normals[i] : SIMD3<Float>(0, 1, 0)
            let n4 = chunk.transform * SIMD4<Float>(nLocal.x, nLocal.y, nLocal.z, 0)
            let nWorld = simd_normalize(SIMD3(n4.x, n4.y, n4.z))

            let newIdx = positions.count / 3
            indexMap[i] = newIdx
            positions.append(contentsOf: [local.x, local.y, local.z])
            normals.append(contentsOf: [nLocal.x, nLocal.y, nLocal.z])

            if let (u, v, rgb) = projectUV(world: world, kf: best) {
                uvs.append(u)
                uvs.append(1 - v) // SceneKit V flip
                colorSum += SIMD3(Float(rgb.0), Float(rgb.1), Float(rgb.2))
                colorN += 1
                uvHits += 1
            } else {
                uvs.append(0.5)
                uvs.append(0.5)
                if let rgb = sampleAny(world: world, normal: nWorld, keyframes: keyframes) {
                    colorSum += SIMD3(Float(rgb.0), Float(rgb.1), Float(rgb.2))
                    colorN += 1
                }
            }
        }

        // Remap indices
        var newIndices: [UInt32] = []
        newIndices.reserveCapacity(chunk.indices.count)
        let triCount = chunk.indices.count / 3
        let triStep = triCount > 60_000 ? 2 : 1
        for t in stride(from: 0, to: triCount, by: triStep) {
            let a = Int(chunk.indices[t * 3])
            let b = Int(chunk.indices[t * 3 + 1])
            let c = Int(chunk.indices[t * 3 + 2])
            // Map to nearest kept vertex if strided
            func map(_ i: Int) -> UInt32? {
                if let m = indexMap[i] { return UInt32(m) }
                // snap down to stride
                let snapped = (i / strideV) * strideV
                if let m = indexMap[snapped] { return UInt32(m) }
                return nil
            }
            guard let ia = map(a), let ib = map(b), let ic = map(c) else { continue }
            if ia == ib || ib == ic || ia == ic { continue }
            newIndices.append(contentsOf: [ia, ib, ic])
        }
        guard !newIndices.isEmpty, positions.count >= 9 else { return nil }

        let newVCount = positions.count / 3
        let posData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let nrmData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = newIndices.withUnsafeBufferPointer { Data(buffer: $0) }

        let sources: [SCNGeometrySource] = [
            SCNGeometrySource(data: posData, semantic: .vertex, vectorCount: newVCount,
                              usesFloatComponents: true, componentsPerVector: 3,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: nrmData, semantic: .normal, vectorCount: newVCount,
                              usesFloatComponents: true, componentsPerVector: 3,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: uvData, semantic: .texcoord, vectorCount: newVCount,
                              usesFloatComponents: true, componentsPerVector: 2,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 8),
        ]
        let element = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: newIndices.count / 3, bytesPerIndex: 4
        )
        let geom = SCNGeometry(sources: sources, elements: [element])

        let avgColor: UIColor
        if colorN > 0 {
            avgColor = UIColor(
                red: CGFloat(colorSum.x / Float(colorN) / 255),
                green: CGFloat(colorSum.y / Float(colorN) / 255),
                blue: CGFloat(colorSum.z / Float(colorN) / 255),
                alpha: 1
            )
        } else {
            avgColor = UIColor(white: 0.65, alpha: 1)
        }

        let mat = SCNMaterial()
        mat.lightingModel = .lambert
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = true

        // Photo texture when enough UVs landed; else solid average (never white void)
        let uvRatio = Float(uvHits) / Float(max(newVCount, 1))
        if uvRatio > 0.08 {
            // Prefer file path for durable materials
            if let textureDir {
                let texName = "tex_\(index).jpg"
                let texURL = textureDir.appendingPathComponent(texName)
                if let data = best.image.jpegData(compressionQuality: 0.85) {
                    try? data.write(to: texURL, options: .atomic)
                    mat.diffuse.contents = texURL.path
                } else {
                    mat.diffuse.contents = best.image
                }
            } else {
                mat.diffuse.contents = best.image
            }
            mat.diffuse.wrapS = .clamp
            mat.diffuse.wrapT = .clamp
            mat.diffuse.magnificationFilter = .linear
            mat.diffuse.minificationFilter = .linear
            mat.diffuse.mipFilter = .linear
        } else {
            mat.diffuse.contents = avgColor
        }
        mat.ambient.contents = UIColor.white
        mat.locksAmbientWithDiffuse = true
        geom.materials = [mat]

        let node = SCNNode(geometry: geom)
        node.simdTransform = chunk.transform
        return node
    }

    // MARK: - Projection

    private static func bestKeyframe(
        for world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> Keyframe? {
        var best: Keyframe?
        var bestScore: Float = -1
        for kf in keyframes {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            if dist < 0.05 || dist > 12 { continue }
            let facing = simd_dot(normal, toCam / dist)
            if facing < 0 { continue }
            let score = facing * (2.5 / max(dist, 0.25))
            if score > bestScore {
                bestScore = score
                best = kf
            }
        }
        return best ?? keyframes.last
    }

    private static func projectUV(
        world: SIMD3<Float>,
        kf: Keyframe
    ) -> (Float, Float, (UInt8, UInt8, UInt8))? {
        let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
        if view.z > -0.02 { return nil }

        let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
        guard projected.x.isFinite, projected.y.isFinite else { return nil }

        let nx = projected.x / max(kf.viewport.width, 1)
        let ny = projected.y / max(kf.viewport.height, 1)
        guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return nil }

        var uv = CGPoint(x: nx, y: ny).applying(kf.displayTransform.inverted())
        if uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1 {
            uv = CGPoint(x: nx, y: ny)
        }
        guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { return nil }

        let rgb = rgbAt(u: Float(uv.x), v: Float(uv.y), kf: kf)
        return (Float(uv.x), Float(uv.y), rgb)
    }

    private static func sampleAny(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8)? {
        for kf in keyframes.reversed() {
            if let p = projectUV(world: world, kf: kf) { return p.2 }
        }
        return nil
    }

    private static func rgbAt(u: Float, v: Float, kf: Keyframe) -> (UInt8, UInt8, UInt8) {
        let w = kf.rgbWidth
        let h = kf.rgbHeight
        guard w > 1, h > 1 else { return (160, 160, 160) }
        let x = min(max(Int(u * Float(w - 1)), 0), w - 1)
        let y = min(max(Int(v * Float(h - 1)), 0), h - 1)
        let o = (y * w + x) * 3
        guard o + 2 < kf.rgb.count else { return (160, 160, 160) }
        return (kf.rgb[o], kf.rgb[o + 1], kf.rgb[o + 2])
    }

    private static func selectKeyframes(_ all: [Keyframe], limit: Int) -> [Keyframe] {
        guard all.count > limit else { return all }
        var result: [Keyframe] = []
        let recent = min(limit * 2 / 3, all.count)
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

    // MARK: - Capture keyframe

    static func makeKeyframe(
        from frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewport: CGSize,
        maxWidth: Int = 400
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
