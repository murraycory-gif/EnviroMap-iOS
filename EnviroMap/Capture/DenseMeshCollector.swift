import Foundation
import ARKit
import SceneKit
import UIKit
import Metal
import simd

/// Collects LiDAR scene-reconstruction mesh while RoomPlan runs,
/// then builds a colored dense mesh of the real space (not only wall boxes).
final class DenseMeshCollector: NSObject {
    private let lock = NSLock()
    private var meshes: [UUID: ARMeshAnchor] = [:]
    private weak var session: ARSession?
    private var isRunning = false

    func attach(to arSession: ARSession) {
        lock.lock()
        // Don’t steal delegate if RoomPlan owns critical callbacks —
        // we use a forwarding approach: set ourselves only if nil, else poll anchors.
        session = arSession
        meshes.removeAll()
        isRunning = true
        lock.unlock()

        // Prefer observing via delegate when free; also poll as backup
        if arSession.delegate == nil {
            arSession.delegate = self
        }
    }

    func stop() {
        lock.lock()
        isRunning = false
        lock.unlock()
    }

    func detach() {
        lock.lock()
        isRunning = false
        if session?.delegate === self {
            session?.delegate = nil
        }
        session = nil
        meshes.removeAll()
        lock.unlock()
    }

    /// Pull latest mesh anchors from the live AR frame (works even if we don’t own the delegate).
    func harvest(from arSession: ARSession?) {
        guard let arSession, let frame = arSession.currentFrame else { return }
        lock.lock()
        guard isRunning else { lock.unlock(); return }
        for anchor in frame.anchors {
            if let mesh = anchor as? ARMeshAnchor {
                meshes[mesh.identifier] = mesh
            }
        }
        lock.unlock()
    }

    var meshCount: Int {
        lock.lock(); defer { lock.unlock() }
        return meshes.count
    }

    func makeColoredScene() -> SCNScene? {
        lock.lock()
        let snapshot = Array(meshes.values)
        lock.unlock()
        guard !snapshot.isEmpty else { return nil }

        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.07, green: 0.09, blue: 0.13, alpha: 1)

        var anyGeometry = false
        for anchor in snapshot {
            if let node = Self.makeNode(from: anchor) {
                scene.rootNode.addChildNode(node)
                anyGeometry = true
            }
        }
        guard anyGeometry else { return nil }

        // Lighting that makes surface color readable
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 550
        ambient.light?.color = UIColor(white: 0.95, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 950
        key.light?.castsShadow = false
        key.eulerAngles = SCNVector3(-0.85, 0.55, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 420
        fill.eulerAngles = SCNVector3(-0.25, -0.9, 0)
        scene.rootNode.addChildNode(fill)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 55
        cam.camera?.wantsHDR = true
        cam.camera?.zNear = 0.05
        cam.camera?.zFar = 50
        cam.position = SCNVector3(3.2, 2.0, 4.2)
        cam.look(at: SCNVector3(0, 1.0, 0))
        scene.rootNode.addChildNode(cam)

        return scene
    }

    @discardableResult
    func export(to directory: URL, preferredName: String = "room_dense.usdz") -> String? {
        guard let scene = makeColoredScene() else { return nil }

        let usdzURL = directory.appendingPathComponent(preferredName)
        if scene.write(to: usdzURL, options: nil) {
            return preferredName
        }
        let scnName = "room_dense.scn"
        let scnURL = directory.appendingPathComponent(scnName)
        if scene.write(to: scnURL, options: nil) {
            return scnName
        }
        return nil
    }

    // MARK: - Convert ARMeshAnchor → SCNNode

    private static func makeNode(from anchor: ARMeshAnchor) -> SCNNode? {
        guard let geometry = makeGeometry(from: anchor.geometry) else { return nil }
        let node = SCNNode(geometry: geometry)
        node.simdTransform = anchor.transform
        node.name = "dense-\(anchor.identifier.uuidString.prefix(8))"
        return node
    }

    private static func makeGeometry(from mesh: ARMeshGeometry) -> SCNGeometry? {
        let vertexSource = mesh.vertices
        let normalSource = mesh.normals
        let faces = mesh.faces

        let vCount = vertexSource.count
        guard vCount > 0, faces.count > 0 else { return nil }

        // --- Vertices ---
        var positions = [Float](repeating: 0, count: vCount * 3)
        for i in 0..<vCount {
            let v = vertex(at: i, from: vertexSource)
            positions[i * 3 + 0] = v.x
            positions[i * 3 + 1] = v.y
            positions[i * 3 + 2] = v.z
        }
        let posData = Data(bytes: &positions, count: positions.count * MemoryLayout<Float>.size)
        let scnVertices = SCNGeometrySource(
            data: posData,
            semantic: .vertex,
            vectorCount: vCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        // --- Normals ---
        var sources: [SCNGeometrySource] = [scnVertices]
        if normalSource.count == vCount {
            var normals = [Float](repeating: 0, count: vCount * 3)
            for i in 0..<vCount {
                let n = vertex(at: i, from: normalSource)
                normals[i * 3 + 0] = n.x
                normals[i * 3 + 1] = n.y
                normals[i * 3 + 2] = n.z
            }
            let nData = Data(bytes: &normals, count: normals.count * MemoryLayout<Float>.size)
            sources.append(
                SCNGeometrySource(
                    data: nData,
                    semantic: .normal,
                    vectorCount: vCount,
                    usesFloatComponents: true,
                    componentsPerVector: 3,
                    bytesPerComponent: MemoryLayout<Float>.size,
                    dataOffset: 0,
                    dataStride: MemoryLayout<Float>.size * 3
                )
            )
        }

        // --- Vertex colors (classification or height heuristic) ---
        var colors = [Float](repeating: 0, count: vCount * 4)
        // Prefer ARMesh classification colors when the buffer has data
        let classCount = mesh.classification.count
        for i in 0..<vCount {
            let c: SIMD4<Float>
            if classCount > 0 {
                let faceIndex = min(i / max(faces.indexCountPerPrimitive, 1), max(faces.count - 1, 0))
                let cls = classification(at: faceIndex, from: mesh.classification)
                c = color(for: cls)
            } else {
                let y = positions[i * 3 + 1]
                if y < 0.12 {
                    c = SIMD4(0.52, 0.42, 0.32, 1) // floor
                } else if y > 2.3 {
                    c = SIMD4(0.94, 0.95, 0.97, 1) // ceiling
                } else {
                    c = SIMD4(0.84, 0.86, 0.88, 1) // walls / clutter
                }
            }
            colors[i * 4 + 0] = c.x
            colors[i * 4 + 1] = c.y
            colors[i * 4 + 2] = c.z
            colors[i * 4 + 3] = c.w
        }
        let cData = Data(bytes: &colors, count: colors.count * MemoryLayout<Float>.size)
        sources.append(
            SCNGeometrySource(
                data: cData,
                semantic: .color,
                vectorCount: vCount,
                usesFloatComponents: true,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 4
            )
        )

        // --- Indices ---
        let primCount = faces.count
        let idxPerPrim = faces.indexCountPerPrimitive
        var indices = [UInt32]()
        indices.reserveCapacity(primCount * idxPerPrim)
        for f in 0..<primCount {
            for c in 0..<idxPerPrim {
                indices.append(faceIndex(face: f, corner: c, element: faces))
            }
        }
        var idxCopy = indices
        let iData = Data(bytes: &idxCopy, count: idxCopy.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: iData,
            primitiveType: .triangles,
            primitiveCount: primCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geom = SCNGeometry(sources: sources, elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.isDoubleSided = true
        mat.roughness.contents = NSNumber(value: 0.88)
        mat.metalness.contents = NSNumber(value: 0.0)
        mat.diffuse.contents = UIColor.white
        // Ensure vertex colors are used
        mat.writesToDepthBuffer = true
        geom.materials = [mat]
        return geom
    }

    private static func vertex(at index: Int, from source: ARGeometrySource) -> SIMD3<Float> {
        let ptr = source.buffer.contents().advanced(by: source.offset + source.stride * index)
        return ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    }

    private static func faceIndex(face: Int, corner: Int, element: ARGeometryElement) -> UInt32 {
        let base = element.buffer.contents().advanced(
            by: (face * element.indexCountPerPrimitive + corner) * element.bytesPerIndex
        )
        if element.bytesPerIndex == 2 {
            return UInt32(base.assumingMemoryBound(to: UInt16.self).pointee)
        }
        return base.assumingMemoryBound(to: UInt32.self).pointee
    }

    private static func classification(at faceIndex: Int, from source: ARGeometrySource) -> ARMeshClassification {
        let idx = min(faceIndex, max(source.count - 1, 0))
        let ptr = source.buffer.contents().advanced(by: source.offset + source.stride * idx)
        let raw = Int(ptr.assumingMemoryBound(to: UInt8.self).pointee)
        return ARMeshClassification(rawValue: raw) ?? .none
    }

    private static func color(for classification: ARMeshClassification) -> SIMD4<Float> {
        switch classification {
        case .wall:    return SIMD4(0.90, 0.91, 0.92, 1)
        case .floor:   return SIMD4(0.55, 0.44, 0.34, 1)
        case .ceiling: return SIMD4(0.96, 0.96, 0.97, 1)
        case .table:   return SIMD4(0.60, 0.46, 0.30, 1)
        case .seat:    return SIMD4(0.32, 0.38, 0.52, 1)
        case .window:  return SIMD4(0.50, 0.72, 0.90, 0.9)
        case .door:    return SIMD4(0.46, 0.30, 0.20, 1)
        case .none:    return SIMD4(0.74, 0.76, 0.78, 1)
        @unknown default:
            return SIMD4(0.72, 0.74, 0.76, 1)
        }
    }
}

// MARK: - ARSessionDelegate (when we own the delegate)

extension DenseMeshCollector: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { ingest(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { ingest(anchors) }
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        lock.lock()
        for a in anchors { meshes.removeValue(forKey: a.identifier) }
        lock.unlock()
    }

    private func ingest(_ anchors: [ARAnchor]) {
        lock.lock()
        guard isRunning else { lock.unlock(); return }
        for a in anchors {
            if let m = a as? ARMeshAnchor { meshes[m.identifier] = m }
        }
        lock.unlock()
    }
}
