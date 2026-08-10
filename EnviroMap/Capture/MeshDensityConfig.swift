import Foundation

/// Live scan is LIGHT (no freezes). Quality comes from good coverage + bake.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    // MARK: Live — hard caps so iPhone never OOM mid-scan

    /// Mesh snapshot rate (seconds)
    static var meshCopyInterval: TimeInterval { 0.28 }

    /// Color frame rate (seconds) — RGB convert is expensive
    static var keyframeInterval: TimeInterval { 0.30 }

    /// Hard cap — more than ~36 full RGB frames risks crash
    static var maxKeyframes: Int { highDetail ? 36 : 28 }

    static var maxChunks: Int { highDetail ? 900 : 600 }

    /// Live RGB width — 360 is sharp enough after bake upscale feel
    static var keyframeMaxWidth: Int { highDetail ? 400 : 320 }

    static var liveVertexSoftCap: Int { 40_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        if vCount > 50_000 { return 3 }
        if vCount > 25_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if faceCount > 35_000 { return 3 }
        if faceCount > 18_000 { return 2 }
        return 1
    }

    /// Final harvest on Done can keep denser geometry
    static var finalVertexSoftCap: Int { highDetail ? 160_000 : 100_000 }

    // MARK: Bake

    static var triangleBudget: Int { highDetail ? 220_000 : 140_000 }
    static var bakeKeyframeLimit: Int { highDetail ? 36 : 28 }
    static var samplesPerTriangle: Int { 3 }
    static var quantizeShift: Int { 3 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 6_000 { return 8 }
        if faceCount > 2_500 { return 6 }
        if faceCount > 1_000 { return 4 }
        return 3
    }
}
