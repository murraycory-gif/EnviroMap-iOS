import Foundation

/// First principles: during the walk, give CPU to ARKit (no live mesh copies).
/// We only harvest full mesh on Finish — denser scan, walk at normal speed.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    /// Color frames while walking (cheap). Faster when moving.
    static func keyframeInterval(movingFast: Bool) -> TimeInterval {
        movingFast ? 0.10 : 0.18
    }

    static var maxKeyframes: Int { 72 }
    static var maxChunks: Int { 4000 }
    /// Higher = sharper color
    static var keyframeMaxWidth: Int { 768 }

    // Live mesh copies DISABLED (0) — ARKit builds denser mesh when we stop fighting it
    static var liveMeshCopyUntilChunks: Int { 0 }
    static var meshCopyInterval: TimeInterval { 999 }
    static var postWarmupMeshInterval: TimeInterval { 999 }

    static func liveVertexStep(vCount: Int) -> Int { 1 }
    static func liveFaceStep(faceCount: Int) -> Int { 1 }

    static var finalVertexSoftCap: Int { 1_200_000 }
    static var triangleBudget: Int { highDetail ? 700_000 : 400_000 }
    static var bakeKeyframeLimit: Int { 72 }
    static var samplesPerTriangle: Int { 3 }
    static var quantizeShift: Int { 2 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        faceCount > 4_000 ? 10 : 5
    }
}
