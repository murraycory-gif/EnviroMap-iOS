import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Fast hybrid bake:
/// - Vertex colors (stable, like 0810-J)
/// - Photo texture ONLY on high-quality projections (no warp)
/// - Light AI fill with hard time budget (never freeze at 78%)
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
        /// 0...1 average luminance — used for dark/bright adaptive scoring
        let meanLuma: Float
    }

    struct BuildResult {
        let scene: SCNScene
        let fileName: String
    }

    static var progressHandler: ((Double, String) -> Void)?

    /// Hard ceiling so bake never hangs on phone
    private static let bakeDeadlineSeconds: CFTimeInterval = 48
    /// Fallback color when paint times out — always visible on dark bg
    private static let visibleGray: (UInt8, UInt8, UInt8) = (168, 172, 178)
    /// Depth colors for hole fill (set only during buildScene)
    private static var bakeDepthSamples: [(SIMD3<Float>, SIMD3<Float>)] = []

    static func makeScene(
        chunks: [CapturedMeshChunk],
        keyframes: [Keyframe],
        depthPoints: [ColoredDepthPoint] = []
    ) -> SCNScene? {
        buildScene(chunks: chunks, keyframes: keyframes, depthPoints: depthPoints)
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
        depthPoints: [ColoredDepthPoint] = [],
        to directory: URL
    ) -> BuildResult? {
        guard let scene = buildScene(chunks: chunks, keyframes: keyframes, depthPoints: depthPoints) else { return nil }
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
        keyframes: [Keyframe],
        depthPoints: [ColoredDepthPoint] = []
    ) -> SCNScene? {
        guard !chunks.isEmpty || !depthPoints.isEmpty else { return nil }
        let t0 = CACurrentMediaTime()
        func timedOut() -> Bool { CACurrentMediaTime() - t0 > bakeDeadlineSeconds }

        progressHandler?(0.06, "Preparing…")

        // Depth → color samples only (no point cloud noise in viewer)
        if depthPoints.isEmpty {
            bakeDepthSamples = []
        } else {
            let step = max(1, depthPoints.count / 25_000)
            var samples: [(SIMD3<Float>, SIMD3<Float>)] = []
            samples.reserveCapacity(min(25_000, depthPoints.count))
            var i = 0
            while i < depthPoints.count {
                let p = depthPoints[i]
                samples.append((p.position, p.color))
                i += step
            }
            bakeDepthSamples = samples
        }

        let kfs = selectKeyframes(keyframes, limit: MeshDensityConfig.bakeKeyframeLimit)
        let photos: [UIImage?] = kfs.map { imageFromRGB($0.rgb, width: $0.rgbWidth, height: $0.rgbHeight) }

        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.08, alpha: 1)
        let root = SCNNode()
        root.name = "coloredMesh"

        let kfCount = max(kfs.count, 1)
        var texPos = Array(repeating: [Float](), count: kfCount)
        var texNrm = Array(repeating: [Float](), count: kfCount)
        var texUV  = Array(repeating: [Float](), count: kfCount)
        var texIdx = Array(repeating: [UInt32](), count: kfCount)
        var texBase = Array(repeating: UInt32(0), count: kfCount)

        var allPos: [Float] = []
        var allNrm: [Float] = []
        var allCol: [Float] = []
        var allIdx: [UInt32] = []
        var base: UInt32 = 0

        // Sparse fill samples (cap small)
        var fillSamples: [(SIMD3<Float>, SIMD3<Float>)] = []
        fillSamples.reserveCapacity(800)

        let total = max(chunks.count, 1)
        let triBudget = MeshDensityConfig.triangleBudget
        var triUsed = 0
        var texTris = 0
        var vcTris = 0

        // Prefer smaller detail chunks first
        let ordered = chunks.sorted { $0.positions.count < $1.positions.count }

        for (ci, chunk) in ordered.enumerated() {
            // NEVER skip chunks — timeout only skips expensive coloring
            let colorBudgetExhausted = timedOut()
            if ci % 2 == 0 {
                let p = 0.08 + 0.70 * Double(ci) / Double(total)
                progressHandler?(min(p, 0.82), colorBudgetExhausted ? "Finishing Mesh…" : "Coloring Surfaces…")
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

            // Color only vertices we emit (lazy cache)
            var colorCache = [Int: (UInt8, UInt8, UInt8)]()
            func colorAt(_ i: Int) -> (UInt8, UInt8, UInt8) {
                if let c = colorCache[i] { return c }
                let c: (UInt8, UInt8, UInt8)
                if colorBudgetExhausted {
                    c = Self.visibleGray
                } else {
                    c = fastColor(world: worldP(i), normal: worldN(i), keyframes: kfs)
                }
                colorCache[i] = c
                // Keep sparse fill samples
                if fillSamples.count < 800, colorCache.count % 12 == 0 {
                    fillSamples.append((
                        worldP(i),
                        SIMD3(Float(c.0) / 255, Float(c.1) / 255, Float(c.2) / 255)
                    ))
                }
                return c
            }

            // Prefer every triangle — only thin extreme tiles (holes > speed)
            var triStep = 1
            // Prefer density — only thin absurd tiles
            if triCount > 250_000 { triStep = 2 }
            if triUsed > triBudget * 2 { triStep = 2 }

            var remap = [Int: UInt32]()

            for ti in stride(from: 0, to: triCount, by: triStep) {
                let i0 = Int(chunk.indices[ti * 3])
                let i1 = Int(chunk.indices[ti * 3 + 1])
                let i2 = Int(chunk.indices[ti * 3 + 2])
                guard i0 < vCount, i1 < vCount, i2 < vCount else { continue }

                let w0 = worldP(i0), w1 = worldP(i1), w2 = worldP(i2)
                let area = simd_length(simd_cross(w1 - w0, w2 - w0))
                if area < 1e-9 { continue }

                let n0 = worldN(i0), n1 = worldN(i1), n2 = worldN(i2)
                let mid = (w0 + w1 + w2) / 3
                let nMid = simd_normalize(n0 + n1 + n2)

                // Photo texture disabled — solid vertex colors only

                // Vertex color (main path)
                func emit(_ i: Int) -> UInt32 {
                    if let e = remap[i] { return e }
                    let w = worldP(i)
                    let n = worldN(i)
                    let c = colorAt(i)
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
                // Subdivide large faces once for sharper color (fewer blurry panels)
                let edge = max(simd_length(w1 - w0), max(simd_length(w2 - w1), simd_length(w0 - w2)))
                if edge > 0.16, triUsed < triBudget {
                    let m01 = (w0 + w1) * 0.5
                    let m12 = (w1 + w2) * 0.5
                    let m20 = (w2 + w0) * 0.5
                    let nm01 = simd_normalize(n0 + n1)
                    let nm12 = simd_normalize(n1 + n2)
                    let nm20 = simd_normalize(n2 + n0)
                    func emitMid(_ w: SIMD3<Float>, _ n: SIMD3<Float>) -> UInt32 {
                        let c: (UInt8, UInt8, UInt8)
                        if colorBudgetExhausted {
                            c = Self.visibleGray
                        } else {
                            c = fastColor(world: w, normal: n, keyframes: kfs)
                        }
                        allPos.append(contentsOf: [w.x, w.y, w.z])
                        allNrm.append(contentsOf: [n.x, n.y, n.z])
                        allCol.append(contentsOf: [
                            Float(c.0) / 255, Float(c.1) / 255, Float(c.2) / 255, 1
                        ])
                        let id = base
                        base += 1
                        return id
                    }
                    let a = emit(i0), b = emit(i1), c = emit(i2)
                    let d = emitMid(m01, nm01)
                    let e = emitMid(m12, nm12)
                    let f = emitMid(m20, nm20)
                    allIdx.append(contentsOf: [a, d, f, d, b, e, f, e, c, d, e, f])
                    vcTris += 4
                    triUsed += 4
                } else {
                    allIdx.append(contentsOf: [emit(i0), emit(i1), emit(i2)])
                    vcTris += 1
                    triUsed += 1
                }
            }
        }

        // LIGHT AI fill — O(verts) with tiny sample set, max ~0.5s
        progressHandler?(0.72, "AI Touch-Up…")
        if !fillSamples.isEmpty, !allCol.isEmpty, !timedOut() {
            lightAIFill(positions: allPos, colors: &allCol, samples: fillSamples, deadline: t0 + bakeDeadlineSeconds)
        }

        progressHandler?(0.88, "Building 3D View…")

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
            geom.materials = [mat]
            let node = SCNNode(geometry: geom)
            node.name = "photoSharp_\(ki)"
            root.addChildNode(node)
        }

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

        // Solid depth patches fill black holes (quads, not grainy points)
        if !depthPoints.isEmpty {
            progressHandler?(0.9, "Filling Gaps…")
            if let fill = makeDepthFillQuads(depthPoints) {
                root.addChildNode(fill)
            }
        }
        progressHandler?(0.92, "Polishing…")

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

        progressHandler?(0.95, "Framing…")
        normalizeForPreview(scene)
        bakeDepthSamples = []
        progressHandler?(1.0, "Ready")
        let dt = CACurrentMediaTime() - t0
        print("[EnviroMap] hybrid \(String(format: "%.1f", dt))s tex=\(texTris) vc=\(vcTris) depth=\(depthPoints.count) kfs=\(kfs.count)")
        return scene
    }



    /// Fills black holes with small solid colored quads from LiDAR depth.
    private static func makeDepthFillQuads(_ points: [ColoredDepthPoint]) -> SCNNode? {
        let maxQuads = 35_000
        let step = max(1, points.count / maxQuads)
        let h: Float = 0.028

        var pos: [Float] = []
        var col: [Float] = []
        var idx: [UInt32] = []
        let cap = min(points.count / max(step, 1), maxQuads)
        pos.reserveCapacity(cap * 12)
        col.reserveCapacity(cap * 16)
        idx.reserveCapacity(cap * 6)

        var base: UInt32 = 0
        var n = 0
        while n < points.count {
            let p = points[n]
            let c = p.color
            let x = p.position.x
            let y = p.position.y
            let z = p.position.z
            // 4 corners of a small world-XZ quad
            pos.append(contentsOf: [x - h, y, z - h])
            col.append(contentsOf: [c.x, c.y, c.z, 1])
            pos.append(contentsOf: [x + h, y, z - h])
            col.append(contentsOf: [c.x, c.y, c.z, 1])
            pos.append(contentsOf: [x + h, y, z + h])
            col.append(contentsOf: [c.x, c.y, c.z, 1])
            pos.append(contentsOf: [x - h, y, z + h])
            col.append(contentsOf: [c.x, c.y, c.z, 1])
            idx.append(contentsOf: [base, base &+ 1, base &+ 2, base, base &+ 2, base &+ 3])
            base &+= 4
            n += step
        }
        guard !pos.isEmpty else { return nil }

        let posData = pos.withUnsafeBufferPointer { Data(buffer: $0) }
        let colData = col.withUnsafeBufferPointer { Data(buffer: $0) }
        let idxData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let sources = [
            SCNGeometrySource(
                data: posData, semantic: .vertex, vectorCount: pos.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            ),
            SCNGeometrySource(
                data: colData, semantic: .color, vectorCount: col.count / 4,
                usesFloatComponents: true, componentsPerVector: 4,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 16
            ),
        ]
        let element = SCNGeometryElement(
            data: idxData, primitiveType: .triangles,
            primitiveCount: idx.count / 3, bytesPerIndex: 4
        )
        let geom = SCNGeometry(sources: sources, elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.diffuse.contents = UIColor.white
        mat.locksAmbientWithDiffuse = true
        geom.materials = [mat]
        let node = SCNNode(geometry: geom)
        node.name = "depthFillQuads"
        node.renderingOrder = -1
        return node
    }

    // MARK: - Fast color (single best frame, limited search)

    private static func fastColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8) {
        guard !keyframes.isEmpty else { return Self.visibleGray }

        var bestW: Float = -1
        var bestC: (UInt8, UInt8, UInt8)?
        var bestLuma: Float = 0.5

        // Prefer well-exposed samples (works dark rooms + bright outdoors)
        for kf in keyframes.reversed() {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            if dist < 0.05 || dist > 8 { continue }
            let viewDir = toCam / max(dist, 1e-4)
            let facing = abs(simd_dot(normal, viewDir))
            if facing < 0.04 { continue }
            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.04 { continue }
            guard let uv = projectUV(world: world, kf: kf) else { continue }
            guard let c = sampleBilinear(kf, u: uv.x, v: uv.y) else { continue }

            let expQ = sampleExposureQuality(c)
            if expQ < 0.08 { continue } // skip pure black / blown white

            let cx = 1 - abs(uv.x - 0.5)
            let cy = 1 - abs(uv.y - 0.5)
            let center = cx * cy
            let frameQ = frameExposureQuality(kf.meanLuma)
            let frameBoost: Float = 0.75 + 0.25 * frameQ
            let distTerm: Float = 1.0 / max(dist, 0.2)
            let centerTerm: Float = 0.35 + 0.65 * center
            let w = Float(facing) * distTerm * centerTerm * expQ * frameBoost
            if w > bestW {
                bestW = w
                bestC = c
                bestLuma = kf.meanLuma
                if w > 3.5 { break }
            }
        }
        if let c = bestC {
            return adaptiveEnhance(c, sceneLuma: bestLuma)
        }

        if let dc = nearestDepthColor(world) {
            return adaptiveEnhance(dc, sceneLuma: 0.45)
        }
        return Self.visibleGray
    }

    /// 0...1 — how usable is this pixel (reject crushed blacks / blown highlights)
    private static func sampleExposureQuality(_ c: (UInt8, UInt8, UInt8)) -> Float {
        let r = Float(c.0)
        let g = Float(c.1)
        let b = Float(c.2)
        let y = (r + g + b) / (3.0 * 255.0)
        let mx = max(r, max(g, b))
        let mn = min(r, min(g, b))
        let sat = mx - mn
        if y > 0.985 && sat < 8 { return 0.15 }
        if y < 0.03 { return 0.35 }
        if y < 0.12 { return 0.7 }
        if y > 0.18 && y < 0.88 { return 1.0 }
        return 0.85
    }

    private static func frameExposureQuality(_ meanLuma: Float) -> Float {
        // Prefer mid-exposed frames; still allow dark/bright
        if meanLuma > 0.2, meanLuma < 0.75 { return 1.0 }
        if meanLuma > 0.12, meanLuma < 0.88 { return 0.7 }
        return 0.45
    }

    private static func nearestDepthColor(_ world: SIMD3<Float>) -> (UInt8, UInt8, UInt8)? {
        let samples = bakeDepthSamples
        guard !samples.isEmpty else { return nil }
        var bestD: Float = 0.18 * 0.18  // 18cm
        var best: SIMD3<Float>?
        // Small search — samples already capped
        for (sp, sc) in samples {
            let d = simd_length_squared(world - sp)
            if d < bestD {
                bestD = d
                best = sc
            }
        }
        guard let sc = best else { return nil }
        return (
            UInt8(min(255, max(0, sc.x * 255))),
            UInt8(min(255, max(0, sc.y * 255))),
            UInt8(min(255, max(0, sc.z * 255)))
        )
    }

    /// O(verts × small samples) with hard deadline — never hangs.
    private static func lightAIFill(
        positions: [Float],
        colors: inout [Float],
        samples: [(SIMD3<Float>, SIMD3<Float>)],
        deadline: CFTimeInterval
    ) {
        let vCount = positions.count / 3
        guard vCount > 0, !samples.isEmpty else { return }

        // Cap work
        let maxVerts = min(vCount, 60_000)
        let step = max(1, vCount / maxVerts)
        let samp = samples.count > 200 ? Array(samples.prefix(200)) : samples

        var i = 0
        var processed = 0
        while i < vCount {
            if processed & 0x7FF == 0, CACurrentMediaTime() > deadline { break }
            let o = i * 4
            guard o + 2 < colors.count else { break }
            let r = colors[o], g = colors[o + 1], b = colors[o + 2]
            let avg = (r + g + b) / 3
            let sat = max(r, max(g, b)) - min(r, min(g, b))
            // Only touch dull/missing
            if avg < 0.28 || sat < 0.05 {
                let p = SIMD3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2])
                var bestD: Float = 0.18
                var best: SIMD3<Float>?
                for (sp, sc) in samp {
                    let d = simd_length_squared(p - sp)
                    if d < bestD * bestD {
                        bestD = sqrt(d)
                        best = sc
                    }
                }
                if let sc = best {
                    let t: Float = 0.65
                    colors[o]     = r * (1 - t) + sc.x * t
                    colors[o + 1] = g * (1 - t) + sc.y * t
                    colors[o + 2] = b * (1 - t) + sc.z * t
                }
            }
            i += step
            processed += 1
        }
    }

    // MARK: - Projection

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
            if dist < 0.12 || dist > 4.5 { continue }
            let viewDir = toCam / max(dist, 1e-4)
            let facing = simd_dot(normal, viewDir)
            if facing < 0.45 { continue }
            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.1 { continue }
            guard let uv = projectUV(world: world, kf: kf) else { continue }
            let center = (1 - abs(uv.x - 0.5)) * (1 - abs(uv.y - 0.5))
            if center < 0.25 { continue }
            let score = facing * facing * (1 / max(dist, 0.3)) * center
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

    // MARK: - Sampling

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
        adaptiveEnhance(c, sceneLuma: 0.5)
    }

    /// Dark rooms: lift shadows. Bright outdoor: tame highlights. Always keep color.
    private static func adaptiveEnhance(
        _ c: (UInt8, UInt8, UInt8),
        sceneLuma: Float
    ) -> (UInt8, UInt8, UInt8) {
        var r = Float(c.0) / 255.0
        var g = Float(c.1) / 255.0
        var bl = Float(c.2) / 255.0
        let y = (r + g + bl) / 3.0

        if sceneLuma < 0.32 || y < 0.28 {
            let lift: Float = 0.12
            r = min(1.0, r + lift * (1.0 - r))
            g = min(1.0, g + lift * (1.0 - g))
            bl = min(1.0, bl + lift * (1.0 - bl))
        } else if sceneLuma > 0.72 || y > 0.82 {
            r = softHighlight(r)
            g = softHighlight(g)
            bl = softHighlight(bl)
        }

        let mid = (r + g + bl) / 3.0
        let contrast: Float = 1.12
        r = clamp01(mid + (r - mid) * contrast)
        g = clamp01(mid + (g - mid) * contrast)
        bl = clamp01(mid + (bl - mid) * contrast)

        let avg = (r + g + bl) / 3.0
        let sat: Float = 1.12
        r = clamp01(avg + (r - avg) * sat)
        g = clamp01(avg + (g - avg) * sat)
        bl = clamp01(avg + (bl - avg) * sat)

        // Soft floor so dark areas stay visible but not milky
        let floor: Float = 0.06
        r = max(r, floor)
        g = max(g, floor)
        bl = max(bl, floor)

        // Micro contrast for clearer edges
        let mid2 = (r + g + bl) / 3.0
        let sharp: Float = 1.08
        r = clamp01(mid2 + (r - mid2) * sharp)
        g = clamp01(mid2 + (g - mid2) * sharp)
        bl = clamp01(mid2 + (bl - mid2) * sharp)

        let ru = UInt8(r * 255.0)
        let gu = UInt8(g * 255.0)
        let bu = UInt8(bl * 255.0)
        return (ru, gu, bu)
    }

    private static func softHighlight(_ v: Float) -> Float {
        if v < 0.7 { return v }
        return 0.7 + (v - 0.7) * 0.55
    }

    private static func clamp01(_ v: Float) -> Float {
        if v < 0 { return 0 }
        if v > 1 { return 1 }
        return v
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

        scene.background.contents = UIColor(white: 0.08, alpha: 1)
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

        // Always keep recent frames
        var result: [Keyframe] = []
        let recentN = min((limit * 2) / 3, all.count)
        result.append(contentsOf: all.suffix(recentN))

        // Fill remaining with exposure diversity (dark + mid + bright)
        let older = Array(all.dropLast(recentN))
        let need = limit - result.count
        if need > 0, !older.isEmpty {
            let dark = older.filter { $0.meanLuma < 0.35 }.suffix(need / 3)
            let bright = older.filter { $0.meanLuma > 0.65 }.suffix(need / 3)
            let mid = older.filter { $0.meanLuma >= 0.35 && $0.meanLuma <= 0.65 }
            result.append(contentsOf: dark)
            result.append(contentsOf: bright)
            let still = need - dark.count - bright.count
            if still > 0, !mid.isEmpty {
                for i in 0..<still {
                    let idx = i * mid.count / still
                    result.append(mid[min(idx, mid.count - 1)])
                }
            }
        }
        // Dedupe by timestamp
        var seen = Set<TimeInterval>()
        var unique: [Keyframe] = []
        for k in result {
            if seen.insert(k.capturedAt).inserted { unique.append(k) }
        }
        return unique
    }

    static func makeKeyframe(
        from frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewport: CGSize,
        maxWidth: Int = MeshDensityConfig.keyframeMaxWidth
    ) -> Keyframe? {
        let cap = min(maxWidth, MeshDensityConfig.keyframeMaxWidth)
        guard var (rgb, w, h) = extractRGB(buffer: frame.capturedImage, maxWidth: cap) else { return nil }

        // Adaptive levels for dark rooms vs bright outdoor before bake
        let mean = applyAdaptiveLevels(&rgb, width: w, height: h)

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
            image: UIImage(),
            meanLuma: mean
        )
    }

    /// Lift shadows in dark frames; tame whites in bright outdoor frames.
    /// Returns mean luma 0...1 after adjustment.
    private static func applyAdaptiveLevels(
        _ rgb: inout [UInt8],
        width: Int,
        height: Int
    ) -> Float {
        let n = width * height
        guard n > 0, rgb.count >= n * 3 else { return 0.5 }

        // Sample mean luma (every 8th pixel for speed)
        var sum: Float = 0
        var cnt = 0
        var i = 0
        while i < n {
            let o = i * 3
            sum += (Float(rgb[o]) + Float(rgb[o + 1]) + Float(rgb[o + 2])) / (3 * 255)
            cnt += 1
            i += 8
        }
        let mean = cnt > 0 ? sum / Float(cnt) : 0.5

        if mean > 0.28, mean < 0.7 {
            return mean // already good — no global remap
        }

        // Dark: gamma < 1 lifts midtones; Bright: gamma > 1 compresses
        let gamma: Float = mean < 0.28 ? 0.78 : 1.25
        let invG = 1.0 / gamma
        for p in 0..<n {
            let o = p * 3
            for c in 0..<3 {
                let v = Float(rgb[o + c]) / 255
                let out = pow(max(v, 0), invG)
                rgb[o + c] = UInt8(min(255, max(0, out * 255)))
            }
        }
        return mean
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
