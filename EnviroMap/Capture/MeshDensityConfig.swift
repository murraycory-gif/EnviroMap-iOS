import Foundation

/// Live scan stays smooth; Done harvest stays dense.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    // Live — stable
    static var meshCopyInterval: TimeInterval { highDetail ? 0.18 : 0.25 }
    static var keyframeInterval: TimeInterval { highDetail ? 0.20 : 0.28 }
    static var maxKeyframes: Int { highDetail ? 56 : 36 }
    static var maxChunks: Int { highDetail ? 2200 : 1400 }
    static var keyframeMaxWidth: Int { highDetail ? 520 : 400 }
    static var liveVertexSoftCap: Int { highDetail ? 90_000 : 55_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        if highDetail {
            if vCount > 70_000 { return 2 }
            return 1
        }
        if vCount > 40_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if highDetail {
            if faceCount > 50_000 { return 2 }
            return 1
        }
        if faceCount > 30_000 { return 2 }
        return 1
    }

    static var finalVertexSoftCap: Int { highDetail ? 220_000 : 140_000 }

    // Bake
    static var triangleBudget: Int { highDetail ? 220_000 : 130_000 }
    static var bakeKeyframeLimit: Int { highDetail ? 36 : 24 }
    static var samplesPerTriangle: Int { highDetail ? 4 : 3 }
    static var quantizeShift: Int { highDetail ? 2 : 3 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 10_000 { return 5 }
        if faceCount > 4_000 { return 4 }
        if faceCount > 1_500 { return 3 }
        return 2
    }
}
