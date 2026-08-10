import Foundation

/// Live: free ARKit (no mesh copies). Finish: full harvest + sharp vertex colors.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    static func keyframeInterval(movingFast: Bool) -> TimeInterval {
        movingFast ? 0.10 : 0.16
    }

    static var maxKeyframes: Int { 80 }
    static var maxChunks: Int { 4000 }
    static var keyframeMaxWidth: Int { 880 }

    static var liveMeshCopyUntilChunks: Int { 0 }
    static var meshCopyInterval: TimeInterval { 999 }
    static var postWarmupMeshInterval: TimeInterval { 999 }

    static func liveVertexStep(vCount: Int) -> Int { 1 }
    static func liveFaceStep(faceCount: Int) -> Int { 1 }

    static var finalVertexSoftCap: Int { 1_200_000 }
    static var triangleBudget: Int { highDetail ? 700_000 : 400_000 }
    static var bakeKeyframeLimit: Int { 64 }
    static var samplesPerTriangle: Int { 1 }
    static var quantizeShift: Int { 2 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        faceCount > 4_000 ? 10 : 5
    }
}
