import Foundation

/// Dense Finish harvest + sharp color bake (speed-safe).
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    static func keyframeInterval(movingFast: Bool) -> TimeInterval {
        // Capture color more often while walking → sharper paint
        movingFast ? 0.09 : 0.14
    }

    static var maxKeyframes: Int { 96 }
    static var maxChunks: Int { 6000 }
    /// Higher = sharper paint detail
    static var keyframeMaxWidth: Int { 800 }

    // Live: still no mesh copies (keep ARKit dense)
    static var liveMeshCopyUntilChunks: Int { 0 }
    static var meshCopyInterval: TimeInterval { 999 }
    static var postWarmupMeshInterval: TimeInterval { 999 }

    static func liveVertexStep(vCount: Int) -> Int { 1 }
    static func liveFaceStep(faceCount: Int) -> Int { 1 }

    static var finalVertexSoftCap: Int { 2_000_000 }
    /// Keep more triangles = fewer holes
    static var triangleBudget: Int { highDetail ? 480_000 : 300_000 }
    static var bakeKeyframeLimit: Int { 40 }
    static var samplesPerTriangle: Int { 1 }
    static var quantizeShift: Int { 2 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        faceCount > 4_000 ? 10 : 5
    }
}
