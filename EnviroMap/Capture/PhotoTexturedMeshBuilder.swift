import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo
import CoreImage

/// Builds a dense LiDAR mesh with **real camera colors** baked onto vertices.
enum PhotoTexturedMeshBuilder {

    struct Keyframe {
        let camera: ARCamera
        let image: CVPixelBuffer
        let orientation: UIInterfaceOrientation
        let viewport: CGSize
        let displayTransform: CGAffineTransform
        let capturedAt: TimeInterval
    }

    static func makeScene(
        anchors: [ARMeshAnchor],
        keyframes: [Keyframe]
    ) -> SCNScene? {
        guard !anchors.isEmpty else { return nil }

        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1)

        var any = false
        for anchor in anchors {
            if let node = node(from: anchor, keyframes: keyframes) {
                scene.rootNode.addChildNode(node)
                any = true
            }
        }
        guard any else { return nil }

        // Soft fill so photo colors stay readable (vertex colors drive appearance)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1200
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 200
        key.eulerAngles = SCNVector3(Float(-0.6), Float(0.4), Float(0))
        scene.rootNode.addChildNode(key)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 60
        cam.camera?.wantsHDR = true
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 80
        cam.position = SCNVector3(Float(2.2), Float(1.5), Float(3.0))
        cam.eulerAngles = SCNVector3(Float(-0.28), Float(0.5), Float(0))
        scene.rootNode.addChildNode(cam)

        return scene
    }

    static func export(
        anchors: [ARMeshAnchor],
        keyframes: [Keyframe],
        to directory: URL,
        name: String = "room_full.usdz"
    ) -> String? {
        guard let scene = makeScene(anchors: anchors, keyframes: keyframes) else { return nil }
        return writeScene(scene, to: directory, name: name)
    }

    /// Preferred path: export from deep-copied chunks (safe after long scans).
    static func exportChunks(
        _ chunks: [CapturedMeshChunk],
        keyframes: [Keyframe],
        to directory: URL,
        name: String = "room_full.usdz"
    ) -> String? {
        guard let scene = makeScene(chunks: chunks, keyframes: keyframes) else { return nil }
        return writeScene(scene, to: directory, name: name)
    }

    private static func writeScene(_ scene: SCNScene, to directory: URL, name: String) -> String? {
        let usdz = directory.appendingPathComponent(name)
        if scene.write(to: usdz, options: nil, delegate: nil, progressHandler: nil) {
            return name
        }
        let scnName = "room_full.scn"
        let scn = directory.appendingPathComponent(scnName)
        if scene.write(to: scn, options: nil, delegate: nil, progressHandler: nil) {
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
        scene.background.contents = UIColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1)

        var any = false
        for chunk in chunks {
            if let node = node(from: chunk, keyframes: keyframes) {
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
        cam.camera?.wantsHDR = true
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 80
        cam.position = SCNVector3(Float(2.2), Float(1.5), Float(3.0))
        cam.eulerAngles = SCNVector3(Float(-0.28), Float(0.5), Float(0))
        scene.rootNode.addChildNode(cam)
        return scene
    }

    private static func node(from chunk: CapturedMeshChunk, keyframes: [Keyframe]) -> SCNNode? {
        guard let geom = geometry(from: chunk, keyframes: keyframes) else { return nil }
        let n = SCNNode(geometry: geom)
        n.simdTransform = chunk.transform
        return n
    }

    private static func geometry(from chunk: CapturedMeshChunk, keyframes: [Keyframe]) -> SCNGeometry? {
        let vCount = chunk.positions.count
        guard vCount > 0, !chunk.indices.isEmpty else { return nil }

        var positions = [Float](repeating: 0, count: vCount * 3)
        var colors = [Float](repeating: 0, count: vCount * 4)
        var normalsArr = [Float](repeating: 0, count: vCount * 3)
        let transform = chunk.transform

        for i in 0..<vCount {
            let local = chunk.positions[i]
            positions[i * 3] = local.x
            positions[i * 3 + 1] = local.y
            positions[i * 3 + 2] = local.z

            let nLocal = i < chunk.normals.count ? chunk.normals[i] : SIMD3<Float>(0, 1, 0)
            normalsArr[i * 3] = nLocal.x
            normalsArr[i * 3 + 1] = nLocal.y
            normalsArr[i * 3 + 2] = nLocal.z

            let world4 = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            let world = SIMD3<Float>(world4.x, world4.y, world4.z)
            let nWorld4 = transform * SIMD4<Float>(nLocal.x, nLocal.y, nLocal.z, 0)
            let nWorld = simd_normalize(SIMD3<Float>(nWorld4.x, nWorld4.y, nWorld4.z))

            if let rgb = sampleBestColor(world: world, normal: nWorld, keyframes: keyframes) {
                colors[i * 4] = rgb.x
                colors[i * 4 + 1] = rgb.y
                colors[i * 4 + 2] = rgb.z
                colors[i * 4 + 3] = 1
            } else {
                let f = fallbackColor(y: world.y)
                colors[i * 4] = f.x
                colors[i * 4 + 1] = f.y
                colors[i * 4 + 2] = f.z
                colors[i * 4 + 3] = 1
            }
        }

        // Convert float colors → byte RGBA for SceneKit reliability
        var bytes = [UInt8](repeating: 0, count: vCount * 4)
        for i in 0..<vCount {
            bytes[i * 4 + 0] = UInt8(clamping: Int(max(0, min(255, colors[i * 4 + 0] * 255))))
            bytes[i * 4 + 1] = UInt8(clamping: Int(max(0, min(255, colors[i * 4 + 1] * 255))))
            bytes[i * 4 + 2] = UInt8(clamping: Int(max(0, min(255, colors[i * 4 + 2] * 255))))
            bytes[i * 4 + 3] = 255
        }

        let sources: [SCNGeometrySource] = [
            source(positions, semantic: .vertex, components: 3, count: vCount),
            source(normalsArr, semantic: .normal, components: 3, count: vCount),
            colorSourceBytes(bytes, count: vCount),
        ]

        var idx = chunk.indices
        let iData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let primCount = chunk.indices.count / 3
        guard primCount > 0 else { return nil }
        let element = SCNGeometryElement(
            data: iData,
            primitiveType: .triangles,
            primitiveCount: primCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geom = SCNGeometry(sources: sources, elements: [element])
        geom.materials = [photoMaterial()]
        return geom
    }

    // MARK: - Geometry

    private static func node(from anchor: ARMeshAnchor, keyframes: [Keyframe]) -> SCNNode? {
        guard let geom = geometry(from: anchor, keyframes: keyframes) else { return nil }
        let n = SCNNode(geometry: geom)
        n.simdTransform = anchor.transform
        return n
    }

    private static func geometry(from anchor: ARMeshAnchor, keyframes: [Keyframe]) -> SCNGeometry? {
        let mesh = anchor.geometry
        let vSource = mesh.vertices
        let nSource = mesh.normals
        let faces = mesh.faces
        let vCount = vSource.count
        guard vCount > 0, faces.count > 0 else { return nil }

        let transform = anchor.transform
        var positions = [Float](repeating: 0, count: vCount * 3)
        var colors = [Float](repeating: 0, count: vCount * 4)
        var normalsArr = [Float](repeating: 0, count: vCount * 3)

        var coloredCount = 0
        for i in 0..<vCount {
            let local = readFloat3(vSource, i)
            positions[i * 3] = local.x
            positions[i * 3 + 1] = local.y
            positions[i * 3 + 2] = local.z

            let world4 = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            let world = SIMD3<Float>(world4.x, world4.y, world4.z)

            let nLocal = readFloat3(nSource, i)
            normalsArr[i * 3] = nLocal.x
            normalsArr[i * 3 + 1] = nLocal.y
            normalsArr[i * 3 + 2] = nLocal.z

            let nWorld4 = transform * SIMD4<Float>(nLocal.x, nLocal.y, nLocal.z, 0)
            let nWorld = simd_normalize(SIMD3<Float>(nWorld4.x, nWorld4.y, nWorld4.z))

            if let rgb = sampleBestColor(world: world, normal: nWorld, keyframes: keyframes) {
                colors[i * 4] = rgb.x
                colors[i * 4 + 1] = rgb.y
                colors[i * 4 + 2] = rgb.z
                colors[i * 4 + 3] = 1
                coloredCount += 1
            } else {
                // Neutral light gray if no sample — never pure white slabs
                let f = fallbackColor(y: world.y)
                colors[i * 4] = f.x
                colors[i * 4 + 1] = f.y
                colors[i * 4 + 2] = f.z
                colors[i * 4 + 3] = 1
            }
        }

        // If almost no photo samples, still export mesh (geometry is valuable)
        _ = coloredCount

        let sources: [SCNGeometrySource] = [
            source(positions, semantic: .vertex, components: 3, count: vCount),
            source(normalsArr, semantic: .normal, components: 3, count: vCount),
            colorSourceBytes({
            var b = [UInt8](repeating: 0, count: vCount * 4)
            for i in 0..<vCount {
                b[i * 4 + 0] = UInt8(clamping: Int(max(0, min(255, colors[i * 4 + 0] * 255))))
                b[i * 4 + 1] = UInt8(clamping: Int(max(0, min(255, colors[i * 4 + 1] * 255))))
                b[i * 4 + 2] = UInt8(clamping: Int(max(0, min(255, colors[i * 4 + 2] * 255))))
                b[i * 4 + 3] = 255
            }
            return b
        }(), count: vCount),
        ]

        var indices = [UInt32]()
        let primCount = faces.count
        let idxPer = faces.indexCountPerPrimitive
        indices.reserveCapacity(primCount * idxPer)
        for f in 0..<primCount {
            for c in 0..<idxPer {
                indices.append(readIndex(faces, face: f, corner: c))
            }
        }
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: iData,
            primitiveType: .triangles,
            primitiveCount: primCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geom = SCNGeometry(sources: sources, elements: [element])
        geom.materials = [photoMaterial()]
        return geom
    }

    /// Vertex-color material — no custom shaders (shaders caused magenta).
    private static func photoMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .lambert
        mat.isDoubleSided = true
        mat.diffuse.contents = UIColor.white
        mat.ambient.contents = UIColor.white
        mat.locksAmbientWithDiffuse = true
        mat.writesToDepthBuffer = true
        mat.readsFromDepthBuffer = true
        mat.fillsMode = .fill
        return mat
    }

    private static func source(
        _ values: [Float],
        semantic: SCNGeometrySource.Semantic,
        components: Int,
        count: Int
    ) -> SCNGeometrySource {
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(
            data: data,
            semantic: semantic,
            vectorCount: count,
            usesFloatComponents: true,
            componentsPerVector: components,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * components
        )
    }

    /// Byte RGBA vertex colors (most reliable in SceneKit).
    private static func colorSourceBytes(_ rgba: [UInt8], count: Int) -> SCNGeometrySource {
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(
            data: data,
            semantic: .color,
            vectorCount: count,
            usesFloatComponents: false,
            componentsPerVector: 4,
            bytesPerComponent: 1,
            dataOffset: 0,
            dataStride: 4
        )
    }

    // MARK: - Color sampling (view → camera image)

    private static func sampleBestColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> SIMD3<Float>? {
        guard !keyframes.isEmpty else { return nil }

        var best: SIMD3<Float>?
        var bestScore: Float = -1

        // Prefer recent keyframes (more likely related to current mesh)
        let frames = keyframes.suffix(48)

        for kf in frames {
            let camPos = SIMD3<Float>(
                kf.camera.transform.columns.3.x,
                kf.camera.transform.columns.3.y,
                kf.camera.transform.columns.3.z
            )
            let toCam = camPos - world
            let dist = simd_length(toCam)
            if dist < 0.08 || dist > 8.0 { continue }

            let toCamN = toCam / dist
            let facing = simd_dot(normal, toCamN)
            // Allow slightly grazing angles for more coverage
            if facing < 0.02 { continue }

            guard let rgb = samplePixel(world: world, keyframe: kf) else { continue }

            // Prefer close + facing + recent
            let score = facing * (1.2 / max(dist, 0.25))
            if score > bestScore {
                bestScore = score
                best = rgb
            }
        }
        return best
    }

    private static func samplePixel(world: SIMD3<Float>, keyframe: Keyframe) -> SIMD3<Float>? {
        let camera = keyframe.camera
        let orientation = keyframe.orientation
        let viewport = keyframe.viewport

        // Behind camera?
        let view = camera.viewMatrix(for: orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
        if view.z >= -0.05 { return nil }

        let projected = camera.projectPoint(world, orientation: orientation, viewportSize: viewport)
        if !projected.x.isFinite || !projected.y.isFinite { return nil }
        if projected.x < -2 || projected.y < -2 ||
            projected.x > viewport.width + 2 || projected.y > viewport.height + 2 {
            return nil
        }

        // Viewport point → normalized → invert displayTransform → image UV
        let nx = projected.x / max(viewport.width, 1)
        let ny = projected.y / max(viewport.height, 1)
        let viewPoint = CGPoint(x: nx, y: ny)
        let imageUV = viewPoint.applying(keyframe.displayTransform.inverted())

        if imageUV.x < 0.0 || imageUV.x > 1.0 || imageUV.y < 0.0 || imageUV.y > 1.0 {
            return nil
        }

        let w = CVPixelBufferGetWidth(keyframe.image)
        let h = CVPixelBufferGetHeight(keyframe.image)
        guard w > 2, h > 2 else { return nil }

        let px = min(max(Int(imageUV.x * CGFloat(w - 1)), 0), w - 1)
        let py = min(max(Int(imageUV.y * CGFloat(h - 1)), 0), h - 1)

        // 3×3 average for less noise
        return averageRGB(buffer: keyframe.image, cx: px, cy: py, radius: 1)
    }

    private static func averageRGB(buffer: CVPixelBuffer, cx: Int, cy: Int, radius: Int) -> SIMD3<Float>? {
        var sum = SIMD3<Float>(0, 0, 0)
        var n: Float = 0
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        for dy in -radius...radius {
            for dx in -radius...radius {
                let x = min(max(cx + dx, 0), w - 1)
                let y = min(max(cy + dy, 0), h - 1)
                if let c = readYCbCrRGB(buffer: buffer, x: x, y: y) {
                    sum += c
                    n += 1
                }
            }
        }
        guard n > 0 else { return nil }
        return sum / n
    }

    private static func readYCbCrRGB(buffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<Float>? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        if format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
                  let cbcrBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
            let yBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let cBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let Y = Float(yBase.advanced(by: y * yBytes + x).assumingMemoryBound(to: UInt8.self).pointee)
            let cx = x / 2
            let cy = y / 2
            let cPtr = cbcrBase.advanced(by: cy * cBytes + cx * 2).assumingMemoryBound(to: UInt8.self)
            let Cb = Float(cPtr[0])
            let Cr = Float(cPtr[1])

            let videoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            let yf = videoRange ? (Y - 16) * (255.0 / 219.0) : Y
            let cb = Cb - 128
            let cr = Cr - 128
            var r = yf + 1.402 * cr
            var g = yf - 0.344136 * cb - 0.714136 * cr
            var b = yf + 1.772 * cb
            r = min(max(r / 255, 0), 1)
            g = min(max(g / 255, 0), 1)
            b = min(max(b / 255, 0), 1)
            // Boost saturation slightly so real materials read better
            let gray = (r + g + b) / 3
            let sat: Float = 1.12
            r = min(max(gray + (r - gray) * sat, 0), 1)
            g = min(max(gray + (g - gray) * sat, 0), 1)
            b = min(max(gray + (b - gray) * sat, 0), 1)
            return SIMD3(r, g, b)
        }

        if format == kCVPixelFormatType_32BGRA {
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let bytes = CVPixelBufferGetBytesPerRow(buffer)
            let ptr = base.advanced(by: y * bytes + x * 4).assumingMemoryBound(to: UInt8.self)
            return SIMD3(Float(ptr[2]) / 255, Float(ptr[1]) / 255, Float(ptr[0]) / 255)
        }
        return nil
    }

    private static func fallbackColor(y: Float) -> SIMD3<Float> {
        if y < 0.12 { return SIMD3(0.42, 0.36, 0.30) }
        if y > 2.3 { return SIMD3(0.88, 0.89, 0.90) }
        return SIMD3(0.72, 0.74, 0.76)
    }

    private static func readFloat3(_ source: ARGeometrySource, _ index: Int) -> SIMD3<Float> {
        let ptr = source.buffer.contents().advanced(by: source.offset + source.stride * index)
        return ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    }

    private static func readIndex(_ element: ARGeometryElement, face: Int, corner: Int) -> UInt32 {
        let off = (face * element.indexCountPerPrimitive + corner) * element.bytesPerIndex
        let base = element.buffer.contents().advanced(by: off)
        if element.bytesPerIndex == 2 {
            return UInt32(base.assumingMemoryBound(to: UInt16.self).pointee)
        }
        return base.assumingMemoryBound(to: UInt32.self).pointee
    }
}
