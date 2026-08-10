import Foundation

/// Smooth live scan even at 100+ mesh pieces; full density only on Finish.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    /// Adaptive mesh rate — slows as coverage grows so UI stays smooth
    static func meshCopyInterval(chunkCount: Int) -> TimeInterval {
        if chunkCount > 140 { return 0.55 }
        if chunkCount > 100 { return 0.40 }
        if chunkCount > 60 { return 0.28 }
        if chunkCount > 30 { return 0.20 }
        return 0.16
    }

    static func keyframeInterval(chunkCount: Int) -> TimeInterval {
        if chunkCount > 140 { return 0.55 }
        if chunkCount > 100 { return 0.42 }
        if chunkCount > 60 { return 0.32 }
        return 0.24
    }

    static var maxKeyframes: Int { 40 }
    static var maxChunks: Int { 2000 }
    static var keyframeMaxWidth: Int { 512 }

    static func liveVertexStep(vCount: Int) -> Int {
        if vCount > 100_000 { return 3 }
        if vCount > 55_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if faceCount > 90_000 { return 3 }
        if faceCount > 45_000 { return 2 }
        return 1
    }

    // Done harvest — keep everything we can
    static var finalVertexSoftCap: Int { 600_000 }
    static var triangleBudget: Int { highDetail ? 420_000 : 260_000 }
    static var bakeKeyframeLimit: Int { 40 }
    static var samplesPerTriangle: Int { 5 }
    static var quantizeShift: Int { 2 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 5_000 { return 10 }
        if faceCount > 2_000 { return 6 }
        return 4
    }
}
