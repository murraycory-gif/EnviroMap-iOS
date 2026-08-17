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
        let orientation: UIInterfaceOrientation
        let viewport: CGSize
        let displayTransform: CGAffineTransform
        let capturedAt: TimeInterval
        let rgb: [UInt8]
        let rgbWidth: Int
        let rgbHeight: Int
        let camPos: SIMD3<Float>
        let image: UIImage
        let meanLuma: Float
        /// Value-type camera (never store ARCamera — it retains ARFrames)
        let view: simd_float4x4
        let proj: simd_float4x4
        let worldToCam: simd_float4x4
        let fx: Float
        let fy: Float
        let cx: Float
        let cy: Float
        let imgW: Float
        let imgH: Float
    }

    struct BuildResult {
        let scene: SCNScene
        let fileName: String
    }

    static var progressHandler: ((Double, String) -> Void)?

    /// Hard ceiling so bake never hangs on phone
    private static let bakeDeadlineSeconds: CFTimeInterval = 22
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
        var photoCache: [Int: UIImage] = [:]
        func photo(_ i: Int) -> UIImage? {
            if let p = photoCache[i] { return p }
            guard i >= 0, i < kfs.count else { return nil }
            let img = imageFromRGB(kfs[i].rgb, width: kfs[i].rgbWidth, height: kfs[i].rgbHeight)
            if let img { photoCache[i] = img }
            return img
        }
        func kiOk(_ i: Int) -> Bool { i >= 0 && i < kfs.count }

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
        var wallPos = Array(repeating: [Float](), count: kfCount)
        var wallNrm = Array(repeating: [Float](), count: kfCount)
        var wallUV  = Array(repeating: [Float](), count: kfCount)
        var wallIdx = Array(repeating: [UInt32](), count: kfCount)
        var wallBase = Array(repeating: UInt32(0), count: kfCount)
        var wallAvgN = Array(repeating: SIMD3<Float>(0, 1, 0), count: kfCount)

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
        // ARKit mesh first (no prebaked colors), then any extras — never let fill wipe the room
        let ordered = chunks.sorted { a, b in
            let aDepth = a.colors != nil
            let bDepth = b.colors != nil
            if aDepth != bDepth { return !aDepth && bDepth }
            return a.positions.count > b.positions.count
        }

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

            // ONE close-up photo per tile. Wide garage shots scored high before
            // and pasted a second Tesla onto the door.
            var chunkKf: Int? = nil
            if !kfs.isEmpty, vCount > 0 {
                var bestScore: Float = -1
                let sampleN = min(vCount, 20)
                for (ki, kf) in kfs.enumerated() {
                    var hits = 0
                    var distSum: Float = 0
                    var minU: Float = 1, maxU: Float = 0, minV: Float = 1, maxV: Float = 0
                    for si in 0..<sampleN {
                        let vi = si * vCount / sampleN
                        let w = worldP(vi)
                        let n = worldN(vi)
                        let toCam = kf.camPos - w
                        let dist = simd_length(toCam)
                        if dist < 0.08 || dist > 4.5 { continue }
                        let facing = abs(simd_dot(n, toCam / max(dist, 1e-4)))
                        if facing < 0.45 { continue }
                        guard let uv = projectUV(world: w, kf: kf) else { continue }
                        hits += 1
                        distSum += dist
                        minU = min(minU, uv.x); maxU = max(maxU, uv.x)
                        minV = min(minV, uv.y); maxV = max(maxV, uv.y)
                    }
                    guard hits >= 6 else { continue }
                    let uvSpan = max(maxU - minU, maxV - minV)
                    if uvSpan > 0.48 { continue }
                    let avgD = distSum / Float(hits)
                    let sharp = Float(max(kf.rgbWidth, 320)) / 640
                    let score = Float(hits) * sharp / max(avgD * avgD, 0.08) / max(uvSpan, 0.03)
                    if score > bestScore {
                        bestScore = score
                        chunkKf = ki
                    }
                }
            }

            // Color only vertices we emit (lazy cache)
            var colorCache = [Int: (UInt8, UInt8, UInt8)]()
            func colorAt(_ i: Int) -> (UInt8, UInt8, UInt8) {
                if let c = colorCache[i] { return c }
                let c: (UInt8, UInt8, UInt8)
                // Depth-fused chunks already carry camera colors
                if let cols = chunk.colors, i < cols.count {
                    let v = cols[i]
                    c = (
                        UInt8(min(255, max(0, v.x * 255))),
                        UInt8(min(255, max(0, v.y * 255))),
                        UInt8(min(255, max(0, v.z * 255)))
                    )
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
            let triStep = 1

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

                // Backdrop walls: always per-triangle photos. Small tiles: one photo.
                var triKf: Int? = (chunk.isBackdrop || vCount >= 800) ? nil : chunkKf
                if triKf == nil || projectUV(world: mid, kf: kfs[triKf!]) == nil {
                    var bestScore: Float = -1
                    for (ki, kf) in kfs.enumerated() {
                        let toCam = kf.camPos - mid
                        let dist = simd_length(toCam)
                        let maxD: Float = chunk.isBackdrop ? 8.0 : 4.2
                        if dist < 0.08 || dist > maxD { continue }
                        let facing = abs(simd_dot(nMid, toCam / max(dist, 1e-4)))
                        if facing < (chunk.isBackdrop ? 0.28 : 0.42) { continue }
                        // Don't stamp the car onto the ceiling — photo must face this surface
                        if chunk.isBackdrop {
                            let m = kf.worldToCam
                            let look = SIMD3<Float>(-m.columns.0.z, -m.columns.1.z, -m.columns.2.z)
                            if simd_dot(look, -nMid) < 0.30 { continue }
                        }
                        if projectUV(world: mid, kf: kf) == nil { continue }
                        let sharp = Float(max(kf.rgbWidth, 320)) / 640
                        let score = facing * sharp / max(dist * dist, 0.18)
                        if score > bestScore {
                            bestScore = score
                            triKf = ki
                        }
                    }
                }
                if let ki = triKf,
                   let u0 = projectUV(world: w0, kf: kfs[ki]),
                   let u1 = projectUV(world: w1, kf: kfs[ki]),
                   let u2 = projectUV(world: w2, kf: kfs[ki]) {
                    let e01 = simd_length(w1 - w0), e12 = simd_length(w2 - w1), e20 = simd_length(w0 - w2)
                    let t01 = simd_length(u1 - u0), t12 = simd_length(u2 - u1), t20 = simd_length(u0 - u2)
                    let wMax = max(e01, max(e12, e20))
                    let uvArea = abs((u1.x - u0.x) * (u2.y - u0.y) - (u2.x - u0.x) * (u1.y - u0.y))
                    // Skip stretched UVs (that's the AK mess)
                    let stretchOK = chunk.isBackdrop
                        ? (uvArea > 1e-7 && t01 > 1e-6)
                        : (wMax < 1.25 && uvArea > 2e-6 && t01 > 1e-5 && e01 > 1e-4 &&
                            abs((t01 / max(e01, 1e-4)) - (t12 / max(e12, 1e-4))) < 8)
                    if stretchOK {
                        func pushTex(_ w: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
                            if chunk.isBackdrop {
                                wallPos[ki].append(contentsOf: [w.x, w.y, w.z])
                                wallNrm[ki].append(contentsOf: [n.x, n.y, n.z])
                                wallUV[ki].append(contentsOf: [uv.x, 1 - uv.y])
                                wallAvgN[ki] += n
                                let id = wallBase[ki]
                                wallBase[ki] += 1
                                return id
                            }
                            texPos[ki].append(contentsOf: [w.x, w.y, w.z])
                            texNrm[ki].append(contentsOf: [n.x, n.y, n.z])
                            texUV[ki].append(contentsOf: [uv.x, 1 - uv.y])
                            let id = texBase[ki]
                            texBase[ki] += 1
                            return id
                        }
                        let a = pushTex(w0, n0, u0)
                        let bb = pushTex(w1, n1, u1)
                        let c = pushTex(w2, n2, u2)
                        if chunk.isBackdrop {
                            wallIdx[ki].append(contentsOf: [a, bb, c])
                        } else {
                            texIdx[ki].append(contentsOf: [a, bb, c])
                        }
                        triUsed += 1
                        texTris += 1
                        continue
                    }
                }

                if chunk.isBackdrop { continue }

                // Vertex color path
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
                if edge > 0.016, triUsed < triBudget {
                    let m01 = (w0 + w1) * 0.5
                    let m12 = (w1 + w2) * 0.5
                    let m20 = (w2 + w0) * 0.5
                    let nm01 = simd_normalize(n0 + n1)
                    let nm12 = simd_normalize(n1 + n2)
                    let nm20 = simd_normalize(n2 + n0)
                    func emitMid(_ w: SIMD3<Float>, _ n: SIMD3<Float>) -> UInt32 {
                        let c = fastColor(world: w, normal: n, keyframes: kfs)
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
            guard !texIdx[ki].isEmpty, let img = photo(ki) else { continue }
            let geom = makeTexturedGeometry(pos: texPos[ki], nrm: texNrm[ki], uv: texUV[ki], idx: texIdx[ki])
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.diffuse.contents = img
            mat.diffuse.wrapS = .clamp
            mat.diffuse.wrapT = .clamp
            mat.diffuse.magnificationFilter = .linear
            mat.diffuse.minificationFilter = .linear
            mat.diffuse.mipFilter = .linear
            mat.diffuse.maxAnisotropy = 8
            mat.diffuse.contentsTransform = SCNMatrix4Identity
            geom.materials = [mat]
            let node = SCNNode(geometry: geom)
            node.name = "photoSharp_\(ki)"
            root.addChildNode(node)
        }

        for ki in 0..<kfs.count {
            guard !wallIdx[ki].isEmpty, let img = photo(ki) else { continue }
            let geom = makeTexturedGeometry(pos: wallPos[ki], nrm: wallNrm[ki], uv: wallUV[ki], idx: wallIdx[ki])
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = false
            mat.cullMode = .back
            mat.diffuse.contents = img
            mat.diffuse.wrapS = .clamp
            mat.diffuse.wrapT = .clamp
            mat.diffuse.magnificationFilter = .linear
            mat.diffuse.minificationFilter = .linear
            mat.diffuse.mipFilter = .linear
            mat.diffuse.maxAnisotropy = 8
            geom.materials = [mat]
            let node = SCNNode(geometry: geom)
            node.name = "photoWall_\(ki)"
            let n = simd_normalize(wallAvgN[ki])
            node.setValue([n.x, n.y, n.z], forKey: "wallN")
            root.addChildNode(node)
        }

        if !allIdx.isEmpty {
            fillSmallHoles(pos: &allPos, nrm: &allNrm, col: &allCol, idx: &allIdx)
            smoothMesh(pos: &allPos, nrm: &allNrm, col: &allCol, idx: allIdx)
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

        // Depth used only for color samples (nearestDepthColor) — no grainy quads in viewer
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



    /// Depth fill ONLY where mesh is missing — keeps solid surfaces photo-clear.
    private static func makeDepthFillQuads(
        _ points: [ColoredDepthPoint],
        meshPositions: [Float]
    ) -> SCNNode? {
        // Occupancy from main mesh (~6cm voxels)
        var occ = Set<UInt64>()
        occ.reserveCapacity(max(meshPositions.count / 9, 1))
        let inv: Float = 16  // 1/0.0625
        var mi = 0
        while mi + 2 < meshPositions.count {
            let x = meshPositions[mi]
            let y = meshPositions[mi + 1]
            let z = meshPositions[mi + 2]
            let key = voxelKey(x, y, z, inv: inv)
            occ.insert(key)
            mi += 3
        }

        let maxQuads = 28_000
        let step = max(1, points.count / maxQuads)
        let h: Float = 0.018  // smaller = less muddy

        var pos: [Float] = []
        var col: [Float] = []
        var idx: [UInt32] = []
        pos.reserveCapacity(12_000)
        col.reserveCapacity(16_000)
        idx.reserveCapacity(18_000)

        var base: UInt32 = 0
        var n = 0
        var kept = 0
        while n < points.count && kept < maxQuads {
            let p = points[n]
            n += step
            // Skip if mesh already covers this spot
            if occ.contains(voxelKey(p.position.x, p.position.y, p.position.z, inv: inv)) {
                continue
            }
            // Also skip neighbors slightly
            let k2 = voxelKey(p.position.x + 0.04, p.position.y, p.position.z, inv: inv)
            if occ.contains(k2) { continue }

            let c = p.color
            // Mild lift so fill isn't black
            let cr = max(c.x, 0.08)
            let cg = max(c.y, 0.08)
            let cb = max(c.z, 0.08)
            let x = p.position.x, y = p.position.y, z = p.position.z
            pos.append(contentsOf: [x - h, y, z - h, x + h, y, z - h, x + h, y, z + h, x - h, y, z + h])
            for _ in 0..<4 {
                col.append(contentsOf: [cr, cg, cb, 1])
            }
            idx.append(contentsOf: [base, base &+ 1, base &+ 2, base, base &+ 2, base &+ 3])
            base &+= 4
            kept += 1
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

    private static func voxelKey(_ x: Float, _ y: Float, _ z: Float, inv: Float) -> UInt64 {
        let ix = Int32((x * inv).rounded())
        let iy = Int32((y * inv).rounded())
        let iz = Int32((z * inv).rounded())
        return (UInt64(bitPattern: Int64(ix)) & 0x1FFFFF)
            | ((UInt64(bitPattern: Int64(iy)) & 0x1FFFFF) << 21)
            | ((UInt64(bitPattern: Int64(iz)) & 0x1FFFFF) << 42)
    }


    // MARK: - Fast color (single best frame, limited search)

    private static func fastColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8) {
        guard !keyframes.isEmpty else { return (175, 178, 182) }

        var bestW: Float = -1
        var bestC: (UInt8, UInt8, UInt8)?
        var anyC: (UInt8, UInt8, UInt8)?
        var anyD = Float.greatestFiniteMagnitude

        for kf in keyframes.reversed() {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            if dist < 0.04 || dist > 14 { continue }
            if let uv = projectUV(world: world, kf: kf),
               let c = sampleBilinear(kf, u: uv.x, v: uv.y) {
                if dist < anyD {
                    anyD = dist
                    anyC = c
                }
            }
            let viewDir = toCam / max(dist, 1e-4)
            let facing = abs(simd_dot(normal, viewDir))
            if facing < 0.18 { continue } // skip glance / reflection views (purple smear)
            let view = kf.view * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.05 { continue }
            guard let uv = projectUV(world: world, kf: kf) else { continue }
            guard let c = sampleBilinear(kf, u: uv.x, v: uv.y) else { continue }
            let luma = (Float(c.0) + Float(c.1) + Float(c.2)) / (3 * 255)
            if luma > 0.98, facing < 0.35 { continue } // only skip blown specular, keep drywall
            let center = (1 - abs(uv.x - 0.5)) * (1 - abs(uv.y - 0.5))
            let w = Float(facing * facing) * (1 / max(dist * dist, 0.04)) * (0.35 + 0.65 * center)
            if w > bestW {
                bestW = w
                bestC = c
                if w > 8 { break }
            }
        }
        if let c = bestC { return mildEnhance(c) }
        if let c = anyC { return mildEnhance(c) }
        return (170, 172, 176)
    }


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
            if dist < 0.04 || dist > 12 { continue }
            let viewDir = toCam / max(dist, 1e-4)
            let facing = simd_dot(normal, viewDir)
            if facing < 0.38 { continue }
            let view = kf.view * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.08 { continue }
            guard let uv = projectUV(world: world, kf: kf) else { continue }
            let center = (1 - abs(uv.x - 0.5)) * (1 - abs(uv.y - 0.5))
            if center < 0.18 { continue }
            // Prefer closer frames (sharper detail)
            let score = facing * facing * (1 / max(dist, 0.25)) * center * center
            if best == nil || score > best!.score {
                best = ProjPick(index: i, score: score)
            }
        }
        return best
    }

    private static func projectUV(world: SIMD3<Float>, kf: Keyframe) -> SIMD2<Float>? {
        // 1) Pinhole in captured-image pixels
        let local = kf.worldToCam * SIMD4<Float>(world.x, world.y, world.z, 1)
        let depth = -local.z
        if depth > 0.08, depth < 8, kf.imgW > 1, kf.imgH > 1 {
            let u = (kf.fx * (local.x / depth) + kf.cx) / kf.imgW
            let v = (kf.fy * (local.y / depth) + kf.cy) / kf.imgH
            if u.isFinite, v.isFinite, u >= 0.012, u <= 0.988, v >= 0.012, v <= 0.988 {
                return SIMD2(u, v)
            }
        }
        // 2) Screen projection fallback (this is what painted the Tesla blue)
        let clip = kf.proj * kf.view * SIMD4<Float>(world.x, world.y, world.z, 1)
        guard clip.w.isFinite, abs(clip.w) > 1e-6 else { return nil }
        let ndcX = clip.x / clip.w
        let ndcY = clip.y / clip.w
        guard ndcX.isFinite, ndcY.isFinite else { return nil }
        let vpW = max(kf.viewport.width, 1)
        let vpH = max(kf.viewport.height, 1)
        let px = (ndcX * 0.5 + 0.5) * Float(vpW)
        let py = (1 - (ndcY * 0.5 + 0.5)) * Float(vpH)
        let vpNorm = CGPoint(x: CGFloat(px) / vpW, y: CGFloat(py) / vpH)
        let imgNorm = vpNorm.applying(kf.displayTransform.inverted())
        let u = Float(imgNorm.x)
        let v = Float(imgNorm.y)
        guard u.isFinite, v.isFinite, u >= 0.012, u <= 0.988, v >= 0.012, v <= 0.988 else { return nil }
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

    /// Fill small holes only (O(n) loop walk). Never invents walls or cuts the Tesla.
    private static func fillSmallHoles(pos: inout [Float], nrm: inout [Float], col: inout [Float], idx: inout [UInt32]) {
        let vCount0 = pos.count / 3
        guard vCount0 > 8, idx.count >= 6, vCount0 < 900_000 else { return }

        var edgeCount: [UInt64: Int] = [:]
        func ek(_ a: UInt32, _ b: UInt32) -> UInt64 {
            let lo = UInt64(min(a, b)), hi = UInt64(max(a, b))
            return (lo << 32) | hi
        }
        var t = 0
        while t + 2 < idx.count {
            let a = idx[t], b = idx[t + 1], c = idx[t + 2]
            t += 3
            if a == b || b == c || c == a { continue }
            edgeCount[ek(a, b), default: 0] += 1
            edgeCount[ek(b, c), default: 0] += 1
            edgeCount[ek(c, a), default: 0] += 1
        }

        var next: [UInt32: UInt32] = [:]
        var deg: [UInt32: Int] = [:]
        for (k, n) in edgeCount where n == 1 {
            let a = UInt32(k >> 32), b = UInt32(k & 0xFFFF_FFFF)
            if next[a] == nil { next[a] = b } else if next[b] == nil { next[b] = a }
            deg[a, default: 0] += 1
            deg[b, default: 0] += 1
        }

        func P(_ i: Int) -> SIMD3<Float> {
            SIMD3(pos[i*3], pos[i*3+1], pos[i*3+2])
        }

        var seen = Set<UInt32>()
        var loops = 0
        let maxLoops = 280
        for start in next.keys {
            if loops >= maxLoops { break }
            if seen.contains(start) { continue }
            var loop: [UInt32] = [start]
            seen.insert(start)
            var cur = start
            var ok = false
            for _ in 0..<14 {
                guard let nxt = next[cur], !seen.contains(nxt) else {
                    if let nxt = next[cur], nxt == start { ok = loop.count >= 3 }
                    break
                }
                loop.append(nxt)
                seen.insert(nxt)
                cur = nxt
                if next[cur] == start { ok = loop.count >= 3; break }
            }
            guard ok, loop.count >= 3, loop.count <= 10 else { continue }

            var perim: Float = 0
            var maxE: Float = 0
            var csum = SIMD3<Float>(0, 0, 0)
            var nsum = SIMD3<Float>(0, 0, 0)
            var colsum = SIMD4<Float>(0, 0, 0, 0)
            for i in 0..<loop.count {
                let ia = Int(loop[i]), ib = Int(loop[(i + 1) % loop.count])
                guard ia < vCount0, ib < vCount0 else { ok = false; break }
                let d = simd_length(P(ib) - P(ia))
                perim += d
                if d > maxE { maxE = d }
                csum += P(ia)
                nsum += SIMD3(nrm[ia*3], nrm[ia*3+1], nrm[ia*3+2])
                if ia * 4 + 3 < col.count {
                    colsum += SIMD4(col[ia*4], col[ia*4+1], col[ia*4+2], col[ia*4+3])
                }
            }
            // Wall pinholes only — skip car-sized voids and long glass edges
            guard ok, perim > 0.04, perim < 1.65, maxE < 0.55 else { continue }

            let inv = 1 / Float(loop.count)
            let cen = csum * inv
            var nn = nsum * inv
            let nlen = simd_length(nn)
            nn = nlen > 1e-5 ? nn / nlen : SIMD3(0, 1, 0)
            // Must be roughly planar
            var planeErr: Float = 0
            for id in loop {
                let d = abs(simd_dot(P(Int(id)) - cen, nn))
                if d > planeErr { planeErr = d }
            }
            guard planeErr < 0.10 else { continue }

            let avgC = colsum * inv
            let newI = UInt32(pos.count / 3)
            pos.append(contentsOf: [cen.x, cen.y, cen.z])
            nrm.append(contentsOf: [nn.x, nn.y, nn.z])
            col.append(contentsOf: [avgC.x, avgC.y, avgC.z, max(avgC.w, 1)])
            for i in 0..<loop.count {
                idx.append(contentsOf: [loop[i], loop[(i + 1) % loop.count], newI])
            }
            loops += 1
        }
        if loops > 0 {
            print("[EnviroMap] hole-fill loops=\(loops)")
        }
    }

    /// Soft surfaces: averaged normals + neighbor color blend (same orientation only).
    private static func smoothMesh(pos: inout [Float], nrm: inout [Float], col: inout [Float], idx: [UInt32]) {
        let vCount = pos.count / 3
        guard vCount > 3, idx.count >= 3 else { return }

        var accN = Array(repeating: SIMD3<Float>(0, 0, 0), count: vCount)
        var t = 0
        while t + 2 < idx.count {
            let a = Int(idx[t]), b = Int(idx[t + 1]), c = Int(idx[t + 2])
            t += 3
            guard a < vCount, b < vCount, c < vCount else { continue }
            let pa = SIMD3(pos[a*3], pos[a*3+1], pos[a*3+2])
            let pb = SIMD3(pos[b*3], pos[b*3+1], pos[b*3+2])
            let pc = SIMD3(pos[c*3], pos[c*3+1], pos[c*3+2])
            let fn = simd_cross(pb - pa, pc - pa)
            accN[a] += fn; accN[b] += fn; accN[c] += fn
        }
        for i in 0..<vCount {
            let n = simd_normalize(accN[i])
            let nn = n.x.isFinite ? n : SIMD3<Float>(0, 1, 0)
            nrm[i*3] = nn.x; nrm[i*3+1] = nn.y; nrm[i*3+2] = nn.z
        }

        // Do NOT average vertex colors — that turned the Tesla into pixels.
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
        // Tiny pop only — keep the real camera color
        func f(_ x: UInt8) -> Float {
            let v = (Float(x) / 255 - 0.5) * 1.06 + 0.5
            return min(1, max(0, v))
        }
        var r = f(c.0), g = f(c.1), bl = f(c.2)
        let avg = (r + g + bl) / 3
        let sat: Float = 1.08
        r = min(1, max(0, avg + (r - avg) * sat))
        g = min(1, max(0, avg + (g - avg) * sat))
        bl = min(1, max(0, avg + (bl - avg) * sat))
        return (UInt8(r * 255), UInt8(g * 255), UInt8(bl * 255))
    }

    /// Dark rooms: lift shadows. Bright outdoor: tame highlights. Always keep color.
    private static func adaptiveEnhance(
        _ c: (UInt8, UInt8, UInt8),
        sceneLuma: Float
    ) -> (UInt8, UInt8, UInt8) {
        // Real camera color with readable pop (bins, cars, walls stay distinct)
        var r = Float(c.0) / 255.0
        var g = Float(c.1) / 255.0
        var bl = Float(c.2) / 255.0
        let y = (r + g + bl) / 3.0

        if sceneLuma < 0.32 || y < 0.25 {
            let lift: Float = 0.10
            r = min(1.0, r + lift * (1.0 - r))
            g = min(1.0, g + lift * (1.0 - g))
            bl = min(1.0, bl + lift * (1.0 - bl))
        } else if sceneLuma > 0.75 || y > 0.85 {
            r = softHighlight(r)
            g = softHighlight(g)
            bl = softHighlight(bl)
        }

        let mid = (r + g + bl) / 3.0
        let contrast: Float = 1.28
        r = clamp01(mid + (r - mid) * contrast)
        g = clamp01(mid + (g - mid) * contrast)
        bl = clamp01(mid + (bl - mid) * contrast)

        let avg = (r + g + bl) / 3.0
        let sat: Float = 1.28
        r = clamp01(avg + (r - avg) * sat)
        g = clamp01(avg + (g - avg) * sat)
        bl = clamp01(avg + (bl - avg) * sat)

        // Keep darks visible on black background without milky wash
        let floor: Float = 0.05
        r = max(r, floor)
        g = max(g, floor)
        bl = max(bl, floor)

        return (UInt8(r * 255.0), UInt8(g * 255.0), UInt8(bl * 255.0))
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

        let dist = safe * 1.35
        let cam = SCNNode()
        cam.name = "previewCam"
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 50
        cam.camera?.zNear = 0.05
        cam.camera?.zFar = max(200, Double(safe * 40))
        cam.position = SCNVector3(dist * 0.78, safe * 0.22, dist * 0.52)
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

        // Sharpest first, then newest
        let sharp = all.filter { $0.rgbWidth >= 800 }.suffix(limit / 2)
        var result: [Keyframe] = Array(sharp)
        for k in all.reversed() {
            if result.count >= limit { break }
            if !result.contains(where: { $0.capturedAt == k.capturedAt }) {
                result.append(k)
            }
        }
        return result
    }

    struct CameraSnap {
        let timestamp: TimeInterval
        let orientation: UIInterfaceOrientation
        let viewport: CGSize
        let displayTransform: CGAffineTransform
        let camPos: SIMD3<Float>
        let view: simd_float4x4
        let proj: simd_float4x4
        let worldToCam: simd_float4x4
        let fx: Float
        let fy: Float
        let cx: Float
        let cy: Float
        let imgW: Float
        let imgH: Float
    }

    static func snapCamera(from frame: ARFrame, orientation: UIInterfaceOrientation, viewport: CGSize) -> CameraSnap {
        let cam = frame.camera
        return CameraSnap(
            timestamp: frame.timestamp,
            orientation: orientation,
            viewport: viewport,
            displayTransform: frame.displayTransform(for: orientation, viewportSize: viewport),
            camPos: SIMD3(cam.transform.columns.3.x, cam.transform.columns.3.y, cam.transform.columns.3.z),
            view: cam.viewMatrix(for: orientation),
            proj: cam.projectionMatrix(for: orientation, viewportSize: viewport, zNear: 0.01, zFar: 80),
            worldToCam: cam.transform.inverse,
            fx: cam.intrinsics.columns.0.x,
            fy: cam.intrinsics.columns.1.y,
            cx: cam.intrinsics.columns.2.x,
            cy: cam.intrinsics.columns.2.y,
            imgW: Float(CVPixelBufferGetWidth(frame.capturedImage)),
            imgH: Float(CVPixelBufferGetHeight(frame.capturedImage))
        )
    }

    static func makeKeyframe(
        buffer: CVPixelBuffer,
        snap: CameraSnap,
        maxWidth: Int = MeshDensityConfig.keyframeMaxWidth
    ) -> Keyframe? {
        let cap = min(maxWidth, MeshDensityConfig.keyframeMaxWidth)
        guard let (rgb, w, h) = extractRGBFast(buffer: buffer, maxWidth: cap) else { return nil }
        let mean: Float = 0.5
        return Keyframe(
            orientation: snap.orientation,
            viewport: snap.viewport,
            displayTransform: snap.displayTransform,
            capturedAt: snap.timestamp,
            rgb: rgb,
            rgbWidth: w,
            rgbHeight: h,
            camPos: snap.camPos,
            image: UIImage(),
            meanLuma: mean,
            view: snap.view,
            proj: snap.proj,
            worldToCam: snap.worldToCam,
            fx: snap.fx,
            fy: snap.fy,
            cx: snap.cx,
            cy: snap.cy,
            imgW: snap.imgW,
            imgH: snap.imgH
        )
    }

    static func makeKeyframe(
        from frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewport: CGSize,
        maxWidth: Int = MeshDensityConfig.keyframeMaxWidth
    ) -> Keyframe? {
        makeKeyframe(buffer: frame.capturedImage, snap: snapCamera(from: frame, orientation: orientation, viewport: viewport), maxWidth: maxWidth)
    }

    /// Lift shadows in dark frames; tame whites in bright outdoor frames.
    /// Returns mean luma 0...1 after adjustment.
    private static func lumaMean(_ rgb: [UInt8], width: Int, height: Int) -> Float {
        let n = width * height
        guard n > 0, rgb.count >= n * 3 else { return 0.5 }
        var sum: Float = 0
        var cnt = 0
        var i = 0
        while i < n {
            let o = i * 3
            sum += (Float(rgb[o]) + Float(rgb[o + 1]) + Float(rgb[o + 2])) / (3 * 255)
            cnt += 1
            i += 11
        }
        return cnt > 0 ? sum / Float(cnt) : 0.5
    }

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


    /// Integer-step YUV→RGB. Owns the bytes immediately so the ARFrame can be released.
    static func extractRGBFast(buffer: CVPixelBuffer, maxWidth: Int) -> ([UInt8], Int, Int)? {
        let fullW = CVPixelBufferGetWidth(buffer)
        let fullH = CVPixelBufferGetHeight(buffer)
        guard fullW > 1, fullH > 1 else { return nil }
        let w = max(2, min(maxWidth, fullW))
        let h = max(2, fullH * w / fullW)
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
            let yPtr = yBase.assumingMemoryBound(to: UInt8.self)
            let cPtr = cBase.assumingMemoryBound(to: UInt8.self)
            for j in 0..<h {
                let sy0 = min(j * fullH / h, fullH - 1)
                let sy1 = min(sy0 + 1, fullH - 1)
                let yRow0 = yPtr.advanced(by: sy0 * yStride)
                let yRow1 = yPtr.advanced(by: sy1 * yStride)
                let cRow = cPtr.advanced(by: (sy0 / 2) * cStride)
                for i in 0..<w {
                    let sx0 = min(i * fullW / w, fullW - 1)
                    let sx1 = min(sx0 + 1, fullW - 1)
                    var Y = (Float(yRow0[sx0]) + Float(yRow0[sx1]) + Float(yRow1[sx0]) + Float(yRow1[sx1])) * 0.25
                    if videoRange { Y = (Y - 16) * (255.0 / 219.0) }
                    let uv = (sx0 / 2) * 2
                    let Cb = Float(cRow[uv]) - 128
                    let Cr = Float(cRow[uv + 1]) - 128
                    var r = Y + 1.402 * Cr
                    var g = Y - 0.344136 * Cb - 0.714136 * Cr
                    var bl = Y + 1.772 * Cb
                    if r < 0 { r = 0 } else if r > 255 { r = 255 }
                    if g < 0 { g = 0 } else if g > 255 { g = 255 }
                    if bl < 0 { bl = 0 } else if bl > 255 { bl = 255 }
                    let o = (j * w + i) * 3
                    rgb[o] = UInt8(r); rgb[o + 1] = UInt8(g); rgb[o + 2] = UInt8(bl)
                }
            }
            return (rgb, w, h)
        }
        return extractRGB(buffer: buffer, maxWidth: maxWidth, boxFilter: false)
    }

    private static func extractRGB(buffer: CVPixelBuffer, maxWidth: Int, boxFilter: Bool = false) -> ([UInt8], Int, Int)? {
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
                    let Y: Float
                    if boxFilter {
                        let sx1 = min(sx + 1, fullW - 1)
                        let sy1 = min(sy + 1, fullH - 1)
                        let Y0 = Float(yBase.advanced(by: sy * yStride + sx).assumingMemoryBound(to: UInt8.self).pointee)
                        let Y1 = Float(yBase.advanced(by: sy * yStride + sx1).assumingMemoryBound(to: UInt8.self).pointee)
                        let Y2 = Float(yBase.advanced(by: sy1 * yStride + sx).assumingMemoryBound(to: UInt8.self).pointee)
                        let Y3 = Float(yBase.advanced(by: sy1 * yStride + sx1).assumingMemoryBound(to: UInt8.self).pointee)
                        Y = (Y0 + Y1 + Y2 + Y3) * 0.25
                    } else {
                        Y = Float(yBase.advanced(by: sy * yStride + sx).assumingMemoryBound(to: UInt8.self).pointee)
                    }
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
