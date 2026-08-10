import Foundation

/// Butter-smooth live scan. Quality is rebuilt on Done, not during walk.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    // MARK: Live — baby-smooth (lowest sustained load)

    static var meshCopyInterval: TimeInterval { 0.40 }   // ~2.5x/sec max
    static var keyframeInterval: TimeInterval { 0.45 }   // ~2x/sec max
    static var maxKeyframes: Int { 24 }                  // hard RAM ceiling
    static var maxChunks: Int { 500 }
    static var keyframeMaxWidth: Int { 288 }             // tiny RGB buffers
    static var liveVertexSoftCap: Int { 28_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        if vCount > 40_000 { return 4 }
        if vCount > 20_000 { return 3 }
        if vCount > 10_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if faceCount > 25_000 { return 4 }
        if faceCount > 12_000 { return 3 }
        if faceCount > 6_000 { return 2 }
        return 1
    }

    // MARK: Done harvest — denser only when finishing

    static var finalVertexSoftCap: Int { highDetail ? 180_000 : 120_000 }
    static var triangleBudget: Int { highDetail ? 200_000 : 120_000 }
    static var bakeKeyframeLimit: Int { 24 }
    static var samplesPerTriangle: Int { 3 }
    static var quantizeShift: Int { 3 }

    /// Blue wire is optional visual sugar — keep cheap or off
    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 4_000 { return 10 }
        if faceCount > 1_500 { return 7 }
        return 5
    }
}
