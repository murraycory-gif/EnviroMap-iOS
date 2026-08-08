import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Builds colored LiDAR mesh using a **color atlas texture** (always visible).
/// File export embeds PNG on disk so colors survive reload.
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

    struct BuildResult {
        let scene: SCNScene
        let fileName: String // relative name written into directory
    }

    // MARK: - Public export

    /// Builds scene + writes `room_full.scn` and `atlas.png` into directory.
    static func exportChunks(
        _ chunks: [CapturedMeshChunk],
        keyframes: [Keyframe],
        to directory: URL,
        name: String = "room_full.scn"
    ) -> String? {
        guard let built = build(chunks: chunks, keyframes: keyframes, directory: directory) else {
            return nil
        }
        return built.fileName
    }

    /// In-memory scene for instant colored preview (no disk round-trip).
    static func makeScene(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe]
    ) -> SCNScene? {
        build(chunks: chunks, keyframes: keyframes, directory: nil)?.scene
    }

    // MARK: - Core builder

    private static func build(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe],
        directory: URL?
    ) -> BuildResult? {
        guard !chunks.isEmpty else { return nil }

        // Flatten all triangles with sampled colors
        var allPositions: [SIMD3<Float>] = []
        var allNormals: [SIMD3<Float>] = []
        var allColors: [(UInt8, UInt8, UInt8)] = [] // per-vertex after expansion
        var allUVs: [SIMD2<Float>] = []
        var allIndices: [UInt32] = []

        // Atlas: each triangle gets a 2x2 pixel block of solid color
        // Max triangles budget for atlas size
        var triangleColors: [(UInt8, UInt8, UInt8)] = []

        for chunk in chunks {
            let t = chunk.transform
            let vCount = chunk.positions.count
            guard vCount > 0, chunk.indices.count >= 3 else { continue }

            let triCount = chunk.indices.count / 3
            for ti in 0..<triCount {
                let i0 = Int(chunk.indices[ti * 3])
                let i1 = Int(chunk.indices[ti * 3 + 1])
                let i2 = Int(chunk.indices[ti * 3 + 2])
                guard i0 < vCount, i1 < vCount, i2 < vCount else { continue }

                let locals = [chunk.positions[i0], chunk.positions[i1], chunk.positions[i2]]
                var worlds: [SIMD3<Float>] = []
                for p in locals {
                    let w = t * SIMD4<Float>(p.x, p.y, p.z, 1)
                    worlds.append(SIMD3(w.x, w.y, w.z))
                }

                // Sample color at triangle centroid (+ try verts)
                let centroid = (worlds[0] + worlds[1] + worlds[2]) / 3
                var nWorld = SIMD3<Float>(0, 1, 0)
                if i0 < chunk.normals.count {
                    let n = chunk.normals[i0]
                    let nw = t * SIMD4<Float>(n.x, n.y, n.z, 0)
                    nWorld = simd_normalize(SIMD3(nw.x, nw.y, nw.z))
                }

                let rgb = sampleColor(world: centroid, normal: nWorld, keyframes: keyframes)
                    ?? sampleColor(world: worlds[0], normal: nWorld, keyframes: keyframes)
                    ?? sampleColor(world: worlds[1], normal: nWorld, keyframes: keyframes)
                    ?? averageKeyframeColor(keyframes)
                    ?? (160, 160, 165)

                let atlasIndex = triangleColors.count
                triangleColors.append(rgb)

                // UVs point at center of this triangle's atlas cell
                let uv = atlasUV(forTriangle: atlasIndex)

                let base = UInt32(allPositions.count)
                for k in 0..<3 {
                    // Transform to world (bake transform into positions for simpler scene)
                    allPositions.append(worlds[k])
                    if i0 < chunk.normals.count {
                        let ni = [i0, i1, i2][k]
                        let n = ni < chunk.normals.count ? chunk.normals[ni] : SIMD3<Float>(0, 1, 0)
                        let nw = t * SIMD4<Float>(n.x, n.y, n.z, 0)
                        allNormals.append(simd_normalize(SIMD3(nw.x, nw.y, nw.z)))
                    } else {
                        allNormals.append(nWorld)
                    }
                    allColors.append(rgb)
                    allUVs.append(uv)
                }
                allIndices.append(contentsOf: [base, base + 1, base + 2])
            }
        }

        guard !allPositions.isEmpty, !triangleColors.isEmpty else { return nil }

        // Build atlas image
        let atlas = makeAtlasImage(triangleColors: triangleColors)
        guard let atlasImage = atlas else { return nil }

        // Optionally write PNG for durable materials
        var textureContents: Any = atlasImage
        if let directory {
            let pngURL = directory.appendingPathComponent("atlas.png")
            if let data = atlasImage.pngData() {
                try? data.write(to: pngURL, options: .atomic)
                // Prefer file URL so SCN write embeds/reloads correctly
                textureContents = pngURL.path
            }
        }

        let vCount = allPositions.count
        var pos = [Float](repeating: 0, count: vCount * 3)
        var nrm = [Float](repeating: 0, count: vCount * 3)
        var uvs = [Float](repeating: 0, count: vCount * 2)
        var cols = [UInt8](repeating: 255, count: vCount * 4)

        for i in 0..<vCount {
            pos[i * 3] = allPositions[i].x
            pos[i * 3 + 1] = allPositions[i].y
            pos[i * 3 + 2] = allPositions[i].z
            nrm[i * 3] = allNormals[i].x
            nrm[i * 3 + 1] = allNormals[i].y
            nrm[i * 3 + 2] = allNormals[i].z
            uvs[i * 2] = allUVs[i].x
            uvs[i * 2 + 1] = allUVs[i].y
            cols[i * 4] = allColors[i].0
            cols[i * 4 + 1] = allColors[i].1
            cols[i * 4 + 2] = allColors[i].2
            cols[i * 4 + 3] = 255
        }

        let sources: [SCNGeometrySource] = [
            source(pos, semantic: .vertex, components: 3, count: vCount, float: true),
            source(nrm, semantic: .normal, components: 3, count: vCount, float: true),
            source(uvs, semantic: .texcoord, components: 2, count: vCount, float: true),
            byteColorSource(cols, count: vCount),
        ]

        var idx = allIndices
        let prim = idx.count / 3
        let iData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: prim, bytesPerIndex: 4
        )

        let geom = SCNGeometry(sources: sources, elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.diffuse.contents = textureContents
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        mat.diffuse.magnificationFilter = .nearest // keep block colors crisp
        mat.diffuse.minificationFilter = .nearest
        mat.emission.contents = UIColor.black
        mat.transparency = 1.0
        geom.materials = [mat]

        let node = SCNNode(geometry: geom)
        // Already in world space
        node.simdTransform = matrix_identity_float4x4

        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        scene.rootNode.addChildNode(node)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1000
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 60
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 100
        // Frame the mesh roughly
        let bounds = node.boundingBox
        let mid = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )
        let ext = max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z, 1)
        cam.position = SCNVector3(mid.x + ext * 0.9, mid.y + ext * 0.55, mid.z + ext * 1.3)
        cam.eulerAngles = SCNVector3(Float(-0.35), Float(0.45), Float(0))
        scene.rootNode.addChildNode(cam)

        // Write scene file if directory given
        let fileName = "room_full.scn"
        if let directory {
            let url = directory.appendingPathComponent(fileName)
            // Ensure atlas.png exists beside it
            if scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) == false {
                // Still return scene for preview even if write fails
            }
        }

        return BuildResult(scene: scene, fileName: fileName)
    }

    // MARK: - Atlas

    /// 2x2 pixels per triangle in a square atlas
    private static func atlasUV(forTriangle index: Int) -> SIMD2<Float> {
        let cell: Int = 2
        // Atlas side in cells
        let grid = 512 // 512 cells → 1024 px
        let col = index % grid
        let row = index / grid
        // Center of cell in 0...1
        let u = (Float(col) + 0.5) / Float(grid)
        let v = (Float(row) + 0.5) / Float(grid)
        _ = cell
        return SIMD2(u, v)
    }

    private static func makeAtlasImage(triangleColors: [(UInt8, UInt8, UInt8)]) -> UIImage? {
        let grid = 512
        let cell = 2
        let size = grid * cell // 1024
        var rgba = [UInt8](repeating: 255, count: size * size * 4)

        for (index, rgb) in triangleColors.enumerated() {
            let col = index % grid
            let row = index / grid
            if row >= grid { break } // atlas full
            let x0 = col * cell
            let y0 = row * cell
            for dy in 0..<cell {
                for dx in 0..<cell {
                    let x = x0 + dx
                    let y = y0 + dy
                    let o = (y * size + x) * 4
                    rgba[o] = rgb.0
                    rgba[o + 1] = rgb.1
                    rgba[o + 2] = rgb.2
                    rgba[o + 3] = 255
                }
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Sampling

    private static func sampleColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8)? {
        guard !keyframes.isEmpty else { return nil }

        var best: (UInt8, UInt8, UInt8)?
        var bestScore: Float = -1

        for kf in keyframes.reversed() {
            let camPos = SIMD3<Float>(
                kf.camera.transform.columns.3.x,
                kf.camera.transform.columns.3.y,
                kf.camera.transform.columns.3.z
            )
            let toCam = camPos - world
            let dist = simd_length(toCam)
            if dist < 0.05 || dist > 15 { continue }

            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z >= 0 { continue }

            let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
            if !projected.x.isFinite || !projected.y.isFinite { continue }

            let nx = projected.x / max(kf.viewport.width, 1)
            let ny = projected.y / max(kf.viewport.height, 1)
            if nx < 0 || nx > 1 || ny < 0 || ny > 1 { continue }

            var img = CGPoint(x: nx, y: ny).applying(kf.displayTransform.inverted())
            if img.x < 0 || img.x > 1 || img.y < 0 || img.y > 1 {
                img = CGPoint(x: nx, y: ny)
            }
            if img.x < 0 || img.x > 1 || img.y < 0 || img.y > 1 { continue }

            let rgb = rgbAt(u: Float(img.x), v: Float(img.y), kf: kf)
            let facing = max(0.01, simd_dot(normal, toCam / dist))
            let score = facing * (2.0 / max(dist, 0.25))
            if score > bestScore {
                bestScore = score
                best = rgb
            }
        }
        return best
    }

    private static func averageKeyframeColor(_ keyframes: [Keyframe]) -> (UInt8, UInt8, UInt8)? {
        guard let kf = keyframes.last, !kf.rgb.isEmpty else { return nil }
        var r = 0, g = 0, b = 0, n = 0
        // Sample grid across image
        let step = max(1, (kf.rgbWidth * kf.rgbHeight) / 200)
        var i = 0
        while i < kf.rgbWidth * kf.rgbHeight {
            let o = i * 3
            if o + 2 < kf.rgb.count {
                r += Int(kf.rgb[o]); g += Int(kf.rgb[o + 1]); b += Int(kf.rgb[o + 2]); n += 1
            }
            i += step
        }
        guard n > 0 else { return nil }
        return (UInt8(r / n), UInt8(g / n), UInt8(b / n))
    }

    private static func rgbAt(u: Float, v: Float, kf: Keyframe) -> (UInt8, UInt8, UInt8) {
        let w = kf.rgbWidth
        let h = kf.rgbHeight
        guard w > 0, h > 0 else { return (180, 180, 180) }
        let x = min(max(Int(u * Float(w - 1)), 0), w - 1)
        let y = min(max(Int(v * Float(h - 1)), 0), h - 1)
        let o = (y * w + x) * 3
        guard o + 2 < kf.rgb.count else { return (180, 180, 180) }
        return (kf.rgb[o], kf.rgb[o + 1], kf.rgb[o + 2])
    }

    // MARK: - Geometry helpers

    private static func source(
        _ values: [Float],
        semantic: SCNGeometrySource.Semantic,
        components: Int,
        count: Int,
        float: Bool
    ) -> SCNGeometrySource {
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(
            data: data, semantic: semantic, vectorCount: count,
            usesFloatComponents: float, componentsPerVector: components,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 4 * components
        )
    }

    private static func byteColorSource(_ rgba: [UInt8], count: Int) -> SCNGeometrySource {
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(
            data: data, semantic: .color, vectorCount: count,
            usesFloatComponents: false, componentsPerVector: 4,
            bytesPerComponent: 1, dataOffset: 0, dataStride: 4
        )
    }

    // MARK: - Keyframe capture

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
                    // Boost saturation so outdoor scans don't wash to white
                    let gray = (r + g + b) / 3
                    let sat: Float = 1.35
                    r = min(max(gray + (r - gray) * sat, 0), 255)
                    g = min(max(gray + (g - gray) * sat, 0), 255)
                    b = min(max(gray + (b - gray) * sat, 0), 255)
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
