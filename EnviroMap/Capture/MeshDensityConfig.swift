import Foundation

/// Faster fuller capture; Finish does one dense harvest. Higher-res frames = clearer color.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    /// Live mesh copies until this many stored tiles (higher = more coverage, watch lag)
    static var liveMeshCopyUntilChunks: Int { 90 }
    static var meshCopyInterval: TimeInterval { 0.18 }

    /// After warm-up, still sample mesh slowly so we don't miss surfaces
    static var postWarmupMeshInterval: TimeInterval { 0.55 }

    static func keyframeInterval(movingFast: Bool) -> TimeInterval {
        movingFast ? 0.14 : 0.22
    }

    static var maxKeyframes: Int { 64 }
    static var maxChunks: Int { 2800 }
    /// Higher = sharper color (more RAM — capped safely)
    static var keyframeMaxWidth: Int { 720 }

    static func liveVertexStep(vCount: Int) -> Int {
        if vCount > 100_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if faceCount > 90_000 { return 2 }
        return 1
    }

    static var finalVertexSoftCap: Int { 900_000 }
    static var triangleBudget: Int { highDetail ? 550_000 : 320_000 }
    static var bakeKeyframeLimit: Int { 64 }
    static var samplesPerTriangle: Int { 4 }
    static var quantizeShift: Int { 2 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 5_000 { return 12 }
        return 6
    }
}
