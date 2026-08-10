import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo
import CoreGraphics
import ImageIO

/// Photoreal path used by top scan apps:
/// 1) Project each triangle into the best camera photo → UV photo texture (sharp)
/// 2) Vertex-color fallback where no camera saw the surface
///
/// Vertex colors alone look blurry because LiDAR triangles are large and colors smear.
/// Photo textures keep camera detail (like 3D Snap / Polycam).
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
        // Flatten texture images into the .scn package so reloads stay sharp
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
        guard !chunks.isEmpty else { return nil }
        progressHandler?(0.05, "Preparing Photos…")

        let kfs = selectKeyframes(keyframes, limit: MeshDensityConfig.bakeKeyframeLimit)
        // Ensure every keyframe has a real UIImage for materials
        let photos: [UIImage?] = kfs.map { kf -> UIImage? in
            if kf.image.size.width > 2 { return kf.image }
            return imageFromRGB(kf.rgb, width: kf.rgbWidth, height: kf.rgbHeight)
        }

        let scene = SCNScene()
        scene.background.contents = UIColor.black
        let root = SCNNode()
        root.name = "coloredMesh"

        // Per-keyframe buckets for photo-textured triangles
        // kfIndex -> (pos, nrm, uv, indices)
        var texPos: [[Float]] = Array(repeating: [], count: max(kfs.count, 1))
        var texNrm: [[Float]] = Array(repeating: [], count: max(kfs.count, 1))
        var texUV: [[Float]] = Array(repeating: [], count: max(kfs.count, 1))
        var texIdx: [[UInt32]] = Array(repeating: [], count: max(kfs.count, 1))
        var texBase: [UInt32] = Array(repeating: 0, count: max(kfs.count, 1))

        // Fallback vertex-colored mesh for unseen surfaces
        var fbPos: [Float] = []
        var fbNrm: [Float] = []
        var fbCol: [Float] = []
        var fbIdx: [UInt32] = []
        var fbBase: UInt32 = 0

        let total = max(chunks.count, 1)
        let triBudget = MeshDensityConfig.triangleBudget
        var triUsed = 0
        var texTris = 0
        var fbTris = 0

        let ordered = chunks.sorted { $0.positions.count < $1.positions.count }

        for (ci, chunk) in ordered.enumerated() {
            if ci % 2 == 0 {
                progressHandler?(0.08 + 0.7 * Double(ci) / Double(total), "Mapping Photos Onto Mesh…")
            }

            let vCount = chunk.positions.count
            let triCount = chunk.indices.count / 3
            guard vCount >= 3, triCount > 0 else { continue }

            let xform = chunk.transform
            func world(_ i: Int) -> SIMD3<Float> {
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

            let triStep = (triCount > 180_000 || triUsed > triBudget) ? 2 : 1

            for ti in stride(from: 0, to: triCount, by: triStep) {
                let i0 = Int(chunk.indices[ti * 3])
                let i1 = Int(chunk.indices[ti * 3 + 1])
                let i2 = Int(chunk.indices[ti * 3 + 2])
                guard i0 < vCount, i1 < vCount, i2 < vCount else { continue }

                let w0 = world(i0), w1 = world(i1), w2 = world(i2)
                let cross = simd_cross(w1 - w0, w2 - w0)
                if simd_length(cross) < 1e-9 { continue }

                let n0 = worldN(i0), n1 = worldN(i1), n2 = worldN(i2)
                let mid = (w0 + w1 + w2) / 3
                let nMid = simd_normalize(n0 + n1 + n2)

                // Best camera for this triangle
                if let pick = bestProjection(world: mid, normal: nMid, keyframes: kfs) {
                    let ki = pick.index
                    // Project all 3 verts for UVs
                    if let uv0 = projectUV(world: w0, kf: kfs[ki]),
                       let uv1 = projectUV(world: w1, kf: kfs[ki]),
                       let uv2 = projectUV(world: w2, kf: kfs[ki]),
                       photos[ki] != nil {
                        // Reject bad UV triangles (stretch / backface)
                        let area = abs((uv1.x - uv0.x) * (uv2.y - uv0.y) - (uv2.x - uv0.x) * (uv1.y - uv0.y))
                        if area > 1e-8 {
                            func push(_ w: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
                                texPos[ki].append(contentsOf: [w.x, w.y, w.z])
                                texNrm[ki].append(contentsOf: [n.x, n.y, n.z])
                                texUV[ki].append(contentsOf: [uv.x, uv.y])
                                let id = texBase[ki]
                                texBase[ki] += 1
                                return id
                            }
                            let a = push(w0, n0, uv0)
                            let b = push(w1, n1, uv1)
                            let c = push(w2, n2, uv2)
                            texIdx[ki].append(contentsOf: [a, b, c])
                            texTris += 1
                            triUsed += 1
                            continue
                        }
                    }
                }

                // Fallback: sharp vertex color (single best sample)
                let c0 = colorFor(world: w0, normal: n0, keyframes: kfs)
                let c1 = colorFor(world: w1, normal: n1, keyframes: kfs)
                let c2 = colorFor(world: w2, normal: n2, keyframes: kfs)
                func pushFB(_ w: SIMD3<Float>, _ n: SIMD3<Float>, _ c: (UInt8, UInt8, UInt8)) -> UInt32 {
                    fbPos.append(contentsOf: [w.x, w.y, w.z])
                    fbNrm.append(contentsOf: [n.x, n.y, n.z])
                    fbCol.append(contentsOf: [
                        Float(c.0) / 255, Float(c.1) / 255, Float(c.2) / 255, 1
                    ])
                    let id = fbBase
                    fbBase += 1
                    return id
                }
                let a = pushFB(w0, n0, c0)
                let b = pushFB(w1, n1, c1)
                let c = pushFB(w2, n2, c2)
                fbIdx.append(contentsOf: [a, b, c])
                fbTris += 1
                triUsed += 1
            }
        }

        progressHandler?(0.85, "Building Sharp 3D View…")

        // Photo-textured nodes (one material per camera photo)
        for ki in 0..<kfs.count {
            guard !texIdx[ki].isEmpty, let img = photos[ki] else { continue }
            let geom = makeTexturedGeometry(
                pos: texPos[ki], nrm: texNrm[ki], uv: texUV[ki], idx: texIdx[ki]
            )
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.diffuse.contents = img
            mat.diffuse.wrapS = .clamp
            mat.diffuse.wrapT = .clamp
            mat.diffuse.magnificationFilter = .linear
            mat.diffuse.minificationFilter = .linear
            mat.diffuse.mipFilter = .linear
            mat.writesToDepthBuffer = true
            geom.materials = [mat]
            let node = SCNNode(geometry: geom)
            node.name = "photoTex_\(ki)"
            root.addChildNode(node)
        }

        // Vertex-color fallback node
        if !fbIdx.isEmpty {
            let geom = makeVertexColorGeometry(pos: fbPos, nrm: fbNrm, col: fbCol, idx: fbIdx)
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.diffuse.contents = UIColor.white
            mat.locksAmbientWithDiffuse = true
            geom.materials = [mat]
            let node = SCNNode(geometry: geom)
            node.name = "vertexFallback"
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
        ambient.light?.intensity = 1000
        scene.rootNode.addChildNode(ambient)

        normalizeForPreview(scene)
        progressHandler?(1.0, "Ready")
        print("[EnviroMap] bake texTris=\(texTris) fbTris=\(fbTris) kfs=\(kfs.count)")
        return scene
    }

    // MARK: - Geometry helpers

    private static func makeTexturedGeometry(
        pos: [Float], nrm: [Float], uv: [Float], idx: [UInt32]
    ) -> SCNGeometry {
        let posData = pos.withUnsafeBufferPointer { Data(buffer: $0) }
        let nrmData = nrm.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvData = uv.withUnsafeBufferPointer { Data(buffer: $0) }
        let idxData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let sources = [
            SCNGeometrySource(
                data: posData, semantic: .vertex, vectorCount: pos.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            ),
            SCNGeometrySource(
                data: nrmData, semantic: .normal, vectorCount: nrm.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            ),
            SCNGeometrySource(
                data: uvData, semantic: .texcoord, vectorCount: uv.count / 2,
                usesFloatComponents: true, componentsPerVector: 2,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 8
            ),
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
            SCNGeometrySource(
                data: posData, semantic: .vertex, vectorCount: pos.count / 3,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            ),
            SCNGeometrySource(
                data: nrmData, semantic: .normal, vectorCount: nrm.count / 3,
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
        return SCNGeometry(sources: sources, elements: [element])
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
            if dist < 0.08 || dist > 7 { continue }
            let viewDir = toCam / max(dist, 1e-4)
            let facing = simd_dot(normal, viewDir)
            if facing < 0.15 { continue } // need real front-facing for sharp texture

            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.05 { continue }

            guard let uv = projectUV(world: world, kf: kf) else { continue }
            // Prefer centered, close, face-on
            let center = (1 - abs(uv.x - 0.5)) * (1 - abs(uv.y - 0.5))
            let score = facing * facing * (1 / max(dist, 0.2)) * (0.3 + 0.7 * center)
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
        // SceneKit texcoords: origin bottom-left often — AR image top-left; flip V
        let u = Float(imgNorm.x)
        let v = Float(1 - imgNorm.y)
        guard u >= 0.001, u <= 0.999, v >= 0.001, v <= 0.999 else { return nil }
        return SIMD2(u, v)
    }

    // MARK: - Vertex color (fallback)

    private static func colorFor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> (UInt8, UInt8, UInt8) {
        guard !keyframes.isEmpty else { return (180, 180, 185) }

        var bestW: Float = -1
        var bestC: (UInt8, UInt8, UInt8)?

        for kf in keyframes.reversed() {
            let toCam = kf.camPos - world
            let dist = simd_length(toCam)
            if dist < 0.06 || dist > 7 { continue }
            let viewDir = toCam / max(dist, 1e-4)
            let facing = abs(simd_dot(normal, viewDir))
            if facing < 0.05 { continue }
            let view = kf.camera.viewMatrix(for: kf.orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
            if view.z > -0.04 { continue }
            guard let uv = projectUV(world: world, kf: kf) else { continue }
            // projectUV flipped V for SceneKit; sample uses image space (unflip)
            let u = uv.x
            let v = 1 - uv.y
            guard let c = sampleBilinear(kf, u: u, v: v) else { continue }
            let center = (1 - abs(u - 0.5)) * (1 - abs(v - 0.5))
            let w = Float(facing * facing) * (1 / max(dist * dist, 0.04)) * (0.25 + 0.75 * center)
            if w > bestW {
                bestW = w
                bestC = c
            }
        }
        if let c = bestC { return sharpen(c) }
        return (170, 172, 175)
    }

    private static func sampleBilinear(_ kf: Keyframe, u: Float, v: Float) -> (UInt8, UInt8, UInt8)? {
        let fx = u * Float(max(kf.rgbWidth - 1, 1))
        let fy = v * Float(max(kf.rgbHeight - 1, 1))
        let x0 = Int(floor(fx)), y0 = Int(floor(fy))
        let x1 = min(x0 + 1, kf.rgbWidth - 1)
        let y1 = min(y0 + 1, kf.rgbHeight - 1)
        let tx = fx - Float(x0), ty = fy - Float(y0)
        guard let c00 = sample(kf, x0, y0), let c10 = sample(kf, x1, y0),
              let c01 = sample(kf, x0, y1), let c11 = sample(kf, x1, y1) else { return nil }
        func mix(_ a: UInt8, _ b: UInt8, _ t: Float) -> Float { Float(a) * (1 - t) + Float(b) * t }
        let r = mix(c00.0, c10.0, tx) * (1 - ty) + mix(c01.0, c11.0, tx) * ty
        let g = mix(c00.1, c10.1, tx) * (1 - ty) + mix(c01.1, c11.1, tx) * ty
        let b = mix(c00.2, c10.2, tx) * (1 - ty) + mix(c01.2, c11.2, tx) * ty
        return (UInt8(min(255, max(0, r))), UInt8(min(255, max(0, g))), UInt8(min(255, max(0, b))))
    }

    private static func sample(_ kf: Keyframe, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)? {
        let xx = min(max(x, 0), kf.rgbWidth - 1)
        let yy = min(max(y, 0), kf.rgbHeight - 1)
        let o = (yy * kf.rgbWidth + xx) * 3
        guard o + 2 < kf.rgb.count else { return nil }
        return (kf.rgb[o], kf.rgb[o + 1], kf.rgb[o + 2])
    }

    private static func sharpen(_ c: (UInt8, UInt8, UInt8)) -> (UInt8, UInt8, UInt8) {
        func f(_ x: UInt8) -> UInt8 {
            let v = (Float(x) / 255 - 0.5) * 1.15 + 0.5
            return UInt8(min(255, max(0, v * 255)))
        }
        return (f(c.0), f(c.1), f(c.2))
    }

    // MARK: - Image from RGB

    private static func imageFromRGB(_ rgb: [UInt8], width: Int, height: Int) -> UIImage? {
        guard width > 1, height > 1, rgb.count >= width * height * 3 else { return nil }
        // Convert RGB to RGBA for CGImage
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

    // MARK: - Normalize / camera

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
            amb.light?.intensity = 1000
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
        let img = imageFromRGB(rgb, width: w, height: h) ?? UIImage()
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
            image: img
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
