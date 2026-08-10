import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Hybrid bake (best of both worlds):
/// 1) Photo UV texture when projection is clean (sharp detail like 3D Snap)
/// 2) Vertex color when UV would warp (stable look like 0810-J)
/// 3) "AI fill" — multi-view consensus + neighbor flood for holes / missing color
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

    // MARK: - Build hybrid scene

    private static func buildScene(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe]
    ) -> SCNScene? {
        guard !chunks.isEmpty else { return nil }
        progressHandler?(0.05, "AI Mapping Photos…")

        let kfs = selectKeyframes(keyframes, limit: MeshDensityConfig.bakeKeyframeLimit)
        let photos: [UIImage?] = kfs.map { imageFromRGB($0.rgb, width: $0.rgbWidth, height: $0.rgbHeight) }

        let scene = SCNScene()
        scene.background.contents = UIColor.black
        let root = SCNNode()
        root.name = "coloredMesh"

        // Photo-texture buckets (only high-quality projections)
        let kfCount = max(kfs.count, 1)
        var texPos = Array(repeating: [Float](), count: kfCount)
        var texNrm = Array(repeating: [Float](), count: kfCount)
        var texUV  = Array(repeating: [Float](), count: kfCount)
        var texIdx = Array(repeating: [UInt32](), count: kfCount)
        var texBase = Array(repeating: UInt32(0), count: kfCount)

        // Vertex-color body (reliable base)
        var allPos: [Float] = []
        var allNrm: [Float] = []
        var allCol: [Float] = []
        var allIdx: [UInt32] = []
        var base: UInt32 = 0

        // For AI neighbor fill — store world positions with colors
        var fillPoints: [(SIMD3<Float>, SIMD3<Float>)] = [] // position, rgb 0-1

        let total = max(chunks.count, 1)
        let triBudget = MeshDensityConfig.triangleBudget
        var triUsed = 0
        var texTris = 0
        var vcTris = 0

        let ordered = chunks.sorted { $0.positions.count < $1.positions.count }

        for (ci, chunk) in ordered.enumerated() {
            if ci % 2 == 0 {
                progressHandler?(0.08 + 0.55 * Double(ci) / Double(total), "Blending Texture + Color…")
            }

            let vCount = chunk.positions.count
            let triCount = chunk.indices.count / 3
            guard vCount >= 3, triCount > 0 else { continue }

            let xform = chunk.transform
            func worldP(_ i: Int) -> SIMD3<Float> {
                let p = chunk.positions[i]
                let w = xform * SIMD4<Float>(p.x, p.y, p.z, 1)
                return SIMD3(w.x, w.y, w.z)
            }
            func worldN(_ i: Int) -> SIMD3<Float> {
                guard i < chunk.normals.count else { return SIMD3(0, 1, 0) }
                let n = chunk.normals[i]
                let nw = xform * SIMD4<Float>(n.x, n.y, n.z, 0)
                var nn = SIMD3(nw.x, nw.y, nw.z)
                let len = simd_length(nn)
                return len > 1e-6 ? nn / len : SIMD3(0, 1, 0)
            }

            // Precompute per-vertex colors (with AI multi-view)
            var vWorld = [SIMD3<Float>](repeating: .zero, count: vCount)
            var vNrm = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: vCount)
            var vCol = [(UInt8, UInt8, UInt8)](repeating: (175, 178, 182), count: vCount)
            var vHas = [Bool](repeating: false, count: vCount)

            for i in 0..<vCount {
                let w = worldP(i)
                let n = worldN(i)
                vWorld[i] = w
                vNrm[i] = n
                let (c, ok) = aiColor(world: w, normal: n, keyframes: kfs)
                vCol[i] = c
                vHas[i] = ok
            }

            // AI fill missing vertex colors from neighbors in this chunk
            aiFillVertexColors(colors: &vCol, has: &vHas, worlds: vWorld, passes: 3)

            for i in 0..<vCount where vHas[i] {
                let c = vCol[i]
                fillPoints.append((
                    vWorld[i],
                    SIMD3(Float(c.0) / 255, Float(c.1) / 255, Float(c.2) / 255)
                ))
            }

            let triStep = (triCount > 200_000 || triUsed > triBudget) ? 2 : 1
            var remap = [Int: UInt32]()

            for ti in stride(from: 0, to: triCount, by: triStep) {
                let i0 = Int(chunk.indices[ti * 3])
                let i1 = Int(chunk.indices[ti * 3 + 1])
                let i2 = Int(chunk.indices[ti * 3 + 2])
                guard i0 < vCount, i1 < vCount, i2 < vCount else { continue }

                let w0 = vWorld[i0], w1 = vWorld[i1], w2 = vWorld[i2]
                let n0 = vNrm[i0], n1 = vNrm[i1], n2 = vNrm[i2]
                let area = simd_length(simd_cross(w1 - w0, w2 - w0))
                if area < 1e-9 { continue }

                let mid = (w0 + w1 + w2) / 3
                let nMid = simd_normalize(n0 + n1 + n2)

                // --- Try photo texture if projection quality is HIGH ---
                if let pick = bestProjection(world: mid, normal: nMid, keyframes: kfs),
                   pick.score > 0.35,
                   photos[pick.index] != nil,
                   let uv0 = projectUV(world: w0, kf: kfs[pick.index]),
                   let uv1 = projectUV(world: w1, kf: kfs[pick.index]),
                   let uv2 = projectUV(world: w2, kf: kfs[pick.index]) {
                    let uvArea = abs((uv1.x - uv0.x) * (uv2.y - uv0.y) - (uv2.x - uv0.x) * (uv1.y - uv0.y))
                    // Reject stretched / tiny UV triangles (what made K look bad)
                    let maxEdge = max(
                        simd_length(uv1 - uv0),
                        max(simd_length(uv2 - uv1), simd_length(uv0 - uv2))
                    )
                    if uvArea > 1e-6, maxEdge < 0.55, maxEdge > 0.002 {
                        let ki = pick.index
                        func pushT(_ w: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
                            texPos[ki].append(contentsOf: [w.x, w.y, w.z])
                            texNrm[ki].append(contentsOf: [n.x, n.y, n.z])
                            // SceneKit V often flipped vs image
                            texUV[ki].append(contentsOf: [uv.x, 1 - uv.y])
                            let id = texBase[ki]
                            texBase[ki] += 1
                            return id
                        }
                        let a = pushT(w0, n0, uv0)
                        let b = pushT(w1, n1, uv1)
                        let c = pushT(w2, n2, uv2)
                        texIdx[ki].append(contentsOf: [a, b, c])
                        texTris += 1
                        triUsed += 1
                        continue
                    }
                }

                // --- Vertex color path (stable) ---
                func emit(_ i: Int) -> UInt32 {
                    if let e = remap[i] { return e }
                    let w = vWorld[i]
                    let n = vNrm[i]
                    let c = vCol[i]
                    allPos.append(contentsOf: [w.x, w.y, w.z])
                    allNrm.append(contentsOf: [n.x, n.y, n.z])
                    allCol.append(contentsOf: [
                        Float(c.0) / 255, Float(c.1) / 255, Float(c.2) / 255, 1
                    ])
                    let id = base
                    base += 1
                    remap[i] = id
                    return id
                }
                allIdx.append(contentsOf: [emit(i0), emit(i1), emit(i2)])
                vcTris += 1
                triUsed += 1
            }
        }

        progressHandler?(0.78, "AI Filling Gaps…")

        // Second AI pass: recolor any dull/gray vertices from nearby fillPoints
        if !fillPoints.isEmpty, !allCol.isEmpty {
            aiGlobalFill(positions: allPos, colors: &allCol, samples: fillPoints)
        }

        progressHandler?(0.88, "Building Hybrid 3D View…")

        // Photo texture nodes
        for ki in 0..<kfs.count {
            guard !texIdx[ki].isEmpty, let img = photos[ki] else { continue }
            let geom = makeTexturedGeometry(pos: texPos[ki], nrm: texNrm[ki], uv: texUV[ki], idx: texIdx[ki])
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.diffuse.contents = img
            mat.diffuse.wrapS = .clamp
            mat.diffuse.wrapT = .clamp
            mat.diffuse.magnificationFilter = .linear
            mat.diffuse.minificationFilter = .linear
            mat.writesToDepthBuffer = true
            geom.materials = [mat]
            let node = SCNNode(geometry: geom)
            node.name = "photoSharp_\(ki)"
            root.addChildNode(node)
        }

        // Vertex color body
        if !allIdx.isEmpty {
            let geom = makeVertexColorGeometry(pos: allPos, nrm: allNrm, col: allCol, idx: allIdx)
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.diffuse.contents = UIColor.white
            mat.locksAmbientWithDiffuse = true
            geom.materials = [mat]
            let node = SCNNode(geometry: geom)
            node.name = "colorBody"
            root.addChildNode(node)
        }

        guard !root.childNodes.isEmpty else {
            progressHandler?(1, "No Mesh")
            return nil
        }

        scene.rootNode.addChildNode(root)
        let ambient = SCNNode()
        ambient.name = "viewerAmbient"
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1050
        scene.rootNode.addChildNode(ambient)

        normalizeForPreview(scene)
        progressHandler?(1.0, "Ready")
        print("[EnviroMap] hybrid texTris=\(texTris) vcTris=\(vcTris) kfs=\(kfs.count) fillPts=\(fillPoints.count)")
        return scene
    }

    // MARK: - AI color / fill

    /// Multi-view consensus: best frame + soft second for stability (not heavy blur).
    private static func aiColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> ((UInt8, UInt8, UInt8), Bool) {
        guard !keyframes.isEmpty else { return ((175, 178, 182), false) }

        var bestW: Float = -1
        var bestC: (UInt8, UInt8, UInt8)?
        var secondW: Float = -1
        var secondC: (UInt8, UInt8, UInt8)?

        for kf in keyframes.reversed() {
            guard let (c, w) = sampleScore(world: world, normal: normal, kf: kf) else { continue }
            if w > bestW {
                secondW = bestW; secondC = bestC
                bestW = w; bestC = c
            } else if w > secondW {
                secondW = w; secondC = c
            }
        }

        guard let c1 = bestC else { return ((170, 172, 176), false) }
        if let c2 = secondC, secondW > bestW * 0.55 {
            // Light consensus — only when second view agrees-ish
            let r = UInt8(min(255, max(0, Int(Float(c1.0) * 0.75 + Float(c2.0) * 0.25))))
            let g = UInt8(min(255, max(0, Int(Float(c1.1) * 0.75 + Float(c2.1) * 0.25))))
            let b = UInt8(min(255, max(0, Int(Float(c1.2) * 0.75 + Float(c2.2) * 0.25))))
            return (mildEnhance((r, g, b)), true)
        }
        return (mildEnhance(c1), true)
    }

    private static func sampleScore(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        kf: Keyframe
    ) -> ((UInt8, UInt8, UInt8), Float)? {
        let toCam = kf.camPos - world
        let dist = simd_length(toCam)
        if dist < 0.05 || dist > 8 { return nil }
        let viewDir = toCam / max(dist, 1e-4)
        let facing = abs(simd_dot(normal, viewDir))
        if facing < 0.04 { return nil }
        let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
        if view.z > -0.04 { return nil }
        guard let uv = projectUV(world: world, kf: kf) else { return nil }
        guard let c = sampleBilinear(kf, u: uv.x, v: uv.y) else { return nil }
        let center = (1 - abs(uv.x - 0.5)) * (1 - abs(uv.y - 0.5))
        let w = Float(facing) * (1 / max(dist, 0.2)) * (0.4 + 0.6 * center)
        return (c, w)
    }

    /// Flood missing colors from nearest neighbors (mesh hole fill).
    private static func aiFillVertexColors(
        colors: inout [(UInt8, UInt8, UInt8)],
        has: inout [Bool],
        worlds: [SIMD3<Float>],
        passes: Int
    ) {
        let n = colors.count
        guard n > 0 else { return }
        for _ in 0..<passes {
            var next = colors
            var nextHas = has
            for i in 0..<n where !has[i] {
                var r = 0, g = 0, b = 0, cnt = 0
                // Sample a sparse set of known neighbors by distance
                for j in 0..<n where has[j] {
                    let d = simd_length(worlds[i] - worlds[j])
                    if d < 0.12 {
                        r += Int(colors[j].0)
                        g += Int(colors[j].1)
                        b += Int(colors[j].2)
                        cnt += 1
                        if cnt >= 6 { break }
                    }
                }
                if cnt > 0 {
                    next[i] = (UInt8(r / cnt), UInt8(g / cnt), UInt8(b / cnt))
                    nextHas[i] = true
                }
            }
            colors = next
            has = nextHas
        }
    }

    /// Spatial fill for residual gray/dull vertices in final mesh.
    private static func aiGlobalFill(
        positions: [Float],
        colors: inout [Float],
        samples: [(SIMD3<Float>, SIMD3<Float>)]
    ) {
        let vCount = positions.count / 3
        guard vCount > 0, !samples.isEmpty else { return }

        // Cap sample set for speed
        let stride = max(1, samples.count / 2500)
        let pts = stride == 1 ? samples : strideArray(samples, by: stride)

        for i in 0..<vCount {
            let o = i * 4
            guard o + 2 < colors.count else { continue }
            let r = colors[o], g = colors[o + 1], b = colors[o + 2]
            // Only fill very dull / near-gray missing look
            let avg = (r + g + b) / 3
            let sat = max(r, max(g, b)) - min(r, min(g, b))
            if avg > 0.25, sat > 0.06 { continue }

            let p = SIMD3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2])
            var bestD: Float = 0.25
            var best: SIMD3<Float>?
            for (sp, sc) in pts {
                let d = simd_length(p - sp)
                if d < bestD {
                    bestD = d
                    best = sc
                }
            }
            if let sc = best {
                // Blend toward neighbor (AI completion, not overwrite)
                let t: Float = 0.7
                colors[o]     = r * (1 - t) + sc.x * t
                colors[o + 1] = g * (1 - t) + sc.y * t
                colors[o + 2] = b * (1 - t) + sc.z * t
            }
        }
    }

    private static func strideArray<T>(_ arr: [T], by step: Int) -> [T] {
        guard step > 1 else { return arr }
        var out: [T] = []
        out.reserveCapacity(arr.count / step + 1)
        var i = 0
        while i < arr.count {
            out.append(arr[i])
            i += step
        }
        return out
    }

    // MARK: - Projection (strict — only clean UVs)

    private struct ProjPick {
        let index: Int
        let score: Float
    }

    private static func bestProjection(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> ProjPick? {
        var best: ProjPick?
        for (i, kf) in keyframes.enumerated().reversed() {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            if dist < 0.1 || dist > 5.5 { continue }
            let viewDir = toCam / max(dist, 1e-4)
            let facing = simd_dot(normal, viewDir)
            if facing < 0.35 { continue } // strict front-facing for photo tex
            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.08 { continue }
            guard let uv = projectUV(world: world, kf: kf) else { continue }
            let center = (1 - abs(uv.x - 0.5)) * (1 - abs(uv.y - 0.5))
            if center < 0.2 { continue } // avoid edges of photo
            let score = facing * facing * (1 / max(dist, 0.25)) * center
            if best == nil || score > best!.score {
                best = ProjPick(index: i, score: score)
            }
        }
        return best
    }

    private static func projectUV(world: SIMD3<Float>, kf: Keyframe) -> SIMD2<Float>? {
        let projected = kf.camera.projectPoint(world, orientation: kf.orientation, viewportSize: kf.viewport)
        guard projected.x.isFinite, projected.y.isFinite else { return nil }
        let vpW = max(kf.viewport.width, 1)
        let vpH = max(kf.viewport.height, 1)
        let vpNorm = CGPoint(x: projected.x / vpW, y: projected.y / vpH)
        let imgNorm = vpNorm.applying(kf.displayTransform.inverted())
        guard imgNorm.x.isFinite, imgNorm.y.isFinite else { return nil }
        let u = Float(imgNorm.x)
        let v = Float(imgNorm.y)
        guard u >= 0.02, u <= 0.98, v >= 0.02, v <= 0.98 else { return nil }
        return SIMD2(u, v)
    }

    // MARK: - Geometry

    private static func makeTexturedGeometry(
        pos: [Float], nrm: [Float], uv: [Float], idx: [UInt32]
    ) -> SCNGeometry {
        let posData = pos.withUnsafeBufferPointer { Data(buffer: $0) }
        let nrmData = nrm.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvData = uv.withUnsafeBufferPointer { Data(buffer: $0) }
        let idxData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let sources = [
            SCNGeometrySource(data: posData, semantic: .vertex, vectorCount: pos.count / 3,
                              usesFloatComponents: true, componentsPerVector: 3,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: nrmData, semantic: .normal, vectorCount: nrm.count / 3,
                              usesFloatComponents: true, componentsPerVector: 3,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: uvData, semantic: .texcoord, vectorCount: uv.count / 2,
                              usesFloatComponents: true, componentsPerVector: 2,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 8),
        ]
        let element = SCNGeometryElement(
            data: idxData, primitiveType: .triangles,
            primitiveCount: idx.count / 3, bytesPerIndex: 4
        )
        return SCNGeometry(sources: sources, elements: [element])
    }

    private static func makeVertexColorGeometry(
        pos: [Float], nrm: [Float], col: [Float], idx: [UInt32]
    ) -> SCNGeometry {
        let posData = pos.withUnsafeBufferPointer { Data(buffer: $0) }
        let nrmData = nrm.withUnsafeBufferPointer { Data(buffer: $0) }
        let colData = col.withUnsafeBufferPointer { Data(buffer: $0) }
        let idxData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let sources = [
            SCNGeometrySource(data: posData, semantic: .vertex, vectorCount: pos.count / 3,
                              usesFloatComponents: true, componentsPerVector: 3,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: nrmData, semantic: .normal, vectorCount: nrm.count / 3,
                              usesFloatComponents: true, componentsPerVector: 3,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: colData, semantic: .color, vectorCount: col.count / 4,
                              usesFloatComponents: true, componentsPerVector: 4,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 16),
        ]
        let element = SCNGeometryElement(
            data: idxData, primitiveType: .triangles,
            primitiveCount: idx.count / 3, bytesPerIndex: 4
        )
        return SCNGeometry(sources: sources, elements: [element])
    }

    // MARK: - Sampling helpers

    private static func sampleBilinear(_ kf: Keyframe, u: Float, v: Float) -> (UInt8, UInt8, UInt8)? {
        let fx = u * Float(max(kf.rgbWidth - 1, 1))
        let fy = v * Float(max(kf.rgbHeight - 1, 1))
        let x0 = Int(floor(fx)), y0 = Int(floor(fy))
        let x1 = min(x0 + 1, kf.rgbWidth - 1)
        let y1 = min(y0 + 1, kf.rgbHeight - 1)
        let tx = fx - Float(x0), ty = fy - Float(y0)
        guard let c00 = sample(kf, x0, y0), let c10 = sample(kf, x1, y0),
              let c01 = sample(kf, x0, y1), let c11 = sample(kf, x1, y1) else { return nil }
        func mix(_ a: UInt8, _ b: UInt8, _ t: Float) -> Float {
            Float(a) * (1 - t) + Float(b) * t
        }
        let r = mix(c00.0, c10.0, tx) * (1 - ty) + mix(c01.0, c11.0, tx) * ty
        let g = mix(c00.1, c10.1, tx) * (1 - ty) + mix(c01.1, c11.1, tx) * ty
        let b = mix(c00.2, c10.2, tx) * (1 - ty) + mix(c01.2, c11.2, tx) * ty
        return (
            UInt8(min(255, max(0, r))),
            UInt8(min(255, max(0, g))),
            UInt8(min(255, max(0, b)))
        )
    }

    private static func sample(_ kf: Keyframe, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)? {
        let xx = min(max(x, 0), kf.rgbWidth - 1)
        let yy = min(max(y, 0), kf.rgbHeight - 1)
        let o = (yy * kf.rgbWidth + xx) * 3
        guard o + 2 < kf.rgb.count else { return nil }
        return (kf.rgb[o], kf.rgb[o + 1], kf.rgb[o + 2])
    }

    private static func mildEnhance(_ c: (UInt8, UInt8, UInt8)) -> (UInt8, UInt8, UInt8) {
        func f(_ x: UInt8) -> UInt8 {
            let v = (Float(x) / 255 - 0.5) * 1.1 + 0.5
            return UInt8(min(255, max(0, v * 255)))
        }
        return (f(c.0), f(c.1), f(c.2))
    }

    private static func imageFromRGB(_ rgb: [UInt8], width: Int, height: Int) -> UIImage? {
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
            bitsPerComponent: 8, bytesPerRow: width * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Normalize

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
        cam.camera?.fieldOfView = 48
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
            amb.light?.intensity = 1050
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
