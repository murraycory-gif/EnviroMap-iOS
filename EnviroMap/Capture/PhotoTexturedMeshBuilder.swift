import Foundation
import ARKit
import SceneKit
import UIKit
import simd
import CoreVideo

/// Builds a dense LiDAR mesh with **real camera colors** baked onto vertices
/// (the look of full-environment 3D scans — not RoomPlan wall boxes).
enum PhotoTexturedMeshBuilder {

    struct Keyframe {
        let camera: ARCamera
        let image: CVPixelBuffer
        let orientation: UIInterfaceOrientation
        let viewport: CGSize
        let capturedAt: TimeInterval
    }

    /// Merge mesh anchors + bake colors from keyframes (best facing camera wins).
    static func makeScene(
        anchors: [ARMeshAnchor],
        keyframes: [Keyframe]
    ) -> SCNScene? {
        guard !anchors.isEmpty else { return nil }

        let scene = SCNScene()
        scene.background.contents = UIColor.black

        var any = false
        for anchor in anchors {
            if let node = node(from: anchor, keyframes: keyframes) {
                scene.rootNode.addChildNode(node)
                any = true
            }
        }
        guard any else { return nil }

        // Neutral lighting so baked photo colors stay true
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1000
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 60
        cam.camera?.wantsHDR = true
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 80
        cam.position = SCNVector3(Float(2.5), Float(1.6), Float(3.5))
        cam.eulerAngles = SCNVector3(Float(-0.25), Float(0.55), Float(0))
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

    // MARK: - Per-anchor geometry

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

        for i in 0..<vCount {
            let local = readFloat3(vSource, i)
            positions[i * 3] = local.x
            positions[i * 3 + 1] = local.y
            positions[i * 3 + 2] = local.z

            let world4 = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            let world = SIMD3<Float>(world4.x, world4.y, world4.z)

            let nLocal = readFloat3(nSource, i)
            let nWorld4 = transform * SIMD4<Float>(nLocal.x, nLocal.y, nLocal.z, 0)
            let nWorld = simd_normalize(SIMD3<Float>(nWorld4.x, nWorld4.y, nWorld4.z))
            normalsArr[i * 3] = nLocal.x
            normalsArr[i * 3 + 1] = nLocal.y
            normalsArr[i * 3 + 2] = nLocal.z

            let sampled = sampleBestColor(world: world, normal: nWorld, keyframes: keyframes)
            colors[i * 4] = sampled.x
            colors[i * 4 + 1] = sampled.y
            colors[i * 4 + 2] = sampled.z
            colors[i * 4 + 3] = 1
        }

        let posData = dataFromFloats(positions)
        let colData = dataFromFloats(colors)
        let nrmData = dataFromFloats(normalsArr)

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
                usesFloatComponents: true, componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 4
            ),
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
        let mat = SCNMaterial()
        // Unlit-ish so photo colors show as captured
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.diffuse.contents = UIColor.white
        mat.writesToDepthBuffer = true
        geom.materials = [mat]
        return geom
    }

    // MARK: - Color sampling

    /// Pick the keyframe where the camera looks most straight at the surface, then sample RGB.
    private static func sampleBestColor(
        world: SIMD3<Float>,
        normal: SIMD3<Float>,
        keyframes: [Keyframe]
    ) -> SIMD3<Float> {
        guard !keyframes.isEmpty else {
            return fallbackColor(y: world.y)
        }

        var best: SIMD3<Float>?
        var bestScore: Float = -1

        for kf in keyframes {
            let camPos = SIMD3<Float>(
                kf.camera.transform.columns.3.x,
                kf.camera.transform.columns.3.y,
                kf.camera.transform.columns.3.z
            )
            let toCam = simd_normalize(camPos - world)
            // Prefer views where surface faces camera
            let facing = max(0, simd_dot(normal, toCam))
            if facing < 0.15 { continue }

            let dist = simd_length(camPos - world)
            if dist < 0.15 || dist > 6.0 { continue }

            guard let rgb = samplePixel(
                world: world,
                camera: kf.camera,
                image: kf.image,
                orientation: kf.orientation,
                viewport: kf.viewport
            ) else { continue }

            let score = facing * (1.0 / max(dist, 0.3))
            if score > bestScore {
                bestScore = score
                best = rgb
            }
        }

        return best ?? fallbackColor(y: world.y)
    }

    private static func samplePixel(
        world: SIMD3<Float>,
        camera: ARCamera,
        image: CVPixelBuffer,
        orientation: UIInterfaceOrientation,
        viewport: CGSize
    ) -> SIMD3<Float>? {
        // Project to viewport
        let projected = camera.projectPoint(world, orientation: orientation, viewportSize: viewport)
        if projected.x < 0 || projected.y < 0 || projected.x > viewport.width || projected.y > viewport.height {
            return nil
        }
        // Behind camera?
        let local = camera.viewMatrix(for: orientation) * SIMD4<Float>(world.x, world.y, world.z, 1)
        if local.z >= 0 { return nil } // in ARKit camera looks down -Z

        let w = CVPixelBufferGetWidth(image)
        let h = CVPixelBufferGetHeight(image)
        guard w > 1, h > 1 else { return nil }

        // Map viewport → pixel (capturedImage is landscape sensor space; approximate with normalized)
        let nx = projected.x / max(viewport.width, 1)
        let ny = projected.y / max(viewport.height, 1)
        let px = min(max(Int(nx * CGFloat(w - 1)), 0), w - 1)
        let py = min(max(Int(ny * CGFloat(h - 1)), 0), h - 1)

        return readYCbCrRGB(buffer: image, x: px, y: py)
    }

    private static func readYCbCrRGB(buffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<Float>? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        // Bi-planar YUV (typical for ARFrame.capturedImage)
        if format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
                  let cbcrBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
            let yBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let cBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let yPtr = yBase.advanced(by: y * yBytes + x).assumingMemoryBound(to: UInt8.self)
            let Y = Float(yPtr.pointee)

            let cx = x / 2
            let cy = y / 2
            let cPtr = cbcrBase.advanced(by: cy * cBytes + cx * 2).assumingMemoryBound(to: UInt8.self)
            let Cb = Float(cPtr[0])
            let Cr = Float(cPtr[1])

            // BT.601 approximate
            let yf = Y - (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? 16 : 0)
            let cb = Cb - 128
            let cr = Cr - 128
            var r = yf + 1.402 * cr
            var g = yf - 0.344136 * cb - 0.714136 * cr
            var b = yf + 1.772 * cb
            r = min(max(r / 255, 0), 1)
            g = min(max(g / 255, 0), 1)
            b = min(max(b / 255, 0), 1)
            return SIMD3(r, g, b)
        }

        // BGRA fallback
        if format == kCVPixelFormatType_32BGRA {
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let bytes = CVPixelBufferGetBytesPerRow(buffer)
            let ptr = base.advanced(by: y * bytes + x * 4).assumingMemoryBound(to: UInt8.self)
            let b = Float(ptr[0]) / 255
            let g = Float(ptr[1]) / 255
            let r = Float(ptr[2]) / 255
            return SIMD3(r, g, b)
        }

        return nil
    }

    private static func fallbackColor(y: Float) -> SIMD3<Float> {
        if y < 0.15 { return SIMD3(0.45, 0.38, 0.30) }
        if y > 2.2 { return SIMD3(0.92, 0.93, 0.95) }
        return SIMD3(0.78, 0.80, 0.82)
    }

    // MARK: - Buffer helpers

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

    private static func dataFromFloats(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
