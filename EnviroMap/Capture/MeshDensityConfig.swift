import Foundation

/// Capture-first with crash-safe live limits. Vertex-color bake on Done.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    static var meshCopyInterval: TimeInterval { 0.18 }
    static var keyframeInterval: TimeInterval { 0.28 }
    static var maxKeyframes: Int { 40 }
    static var maxChunks: Int { 1800 }
    static var keyframeMaxWidth: Int { 480 }

    static var liveVertexTarget: Int { 48_000 }
    static var liveFaceTarget: Int { 60_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        if vCount > 100_000 { return 3 }
        if vCount > 50_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if faceCount > 80_000 { return 3 }
        if faceCount > 40_000 { return 2 }
        return 1
    }

    static var finalVertexSoftCap: Int { 400_000 }
    static var triangleBudget: Int { highDetail ? 280_000 : 180_000 }
    static var bakeKeyframeLimit: Int { 40 }
    static var samplesPerTriangle: Int { 4 }
    static var quantizeShift: Int { 3 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 5_000 { return 8 }
        if faceCount > 2_000 { return 5 }
        return 3
    }
}
