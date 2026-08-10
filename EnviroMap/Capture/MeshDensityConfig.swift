import Foundation

/// Live stays light (keyframes only after warm-up). Finish pulls full ARKit mesh once.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    /// Live mesh copies only while warming up — then STOP (prevents freeze at "Almost Ready")
    static var liveMeshCopyUntilChunks: Int { 36 }
    static var meshCopyInterval: TimeInterval { 0.35 }

    /// Color frames while walking (cheap vs mesh copy)
    static func keyframeInterval(movingFast: Bool) -> TimeInterval {
        movingFast ? 0.18 : 0.28
    }

    static var maxKeyframes: Int { 56 }
    static var maxChunks: Int { 2500 }
    static var keyframeMaxWidth: Int { 560 }

    static func liveVertexStep(vCount: Int) -> Int {
        if vCount > 80_000 { return 3 }
        if vCount > 40_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if faceCount > 70_000 { return 3 }
        if faceCount > 35_000 { return 2 }
        return 1
    }

    static var finalVertexSoftCap: Int { 800_000 }
    static var triangleBudget: Int { highDetail ? 500_000 : 300_000 }
    static var bakeKeyframeLimit: Int { 56 }
    static var samplesPerTriangle: Int { 5 }
    static var quantizeShift: Int { 2 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 5_000 { return 12 }
        return 6
    }
}
