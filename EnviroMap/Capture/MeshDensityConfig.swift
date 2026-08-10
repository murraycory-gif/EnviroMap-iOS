import Foundation

/// Live = smooth. Done harvest = quality.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    // Live smooth
    static var meshCopyInterval: TimeInterval { 0.35 }
    static var keyframeInterval: TimeInterval { 0.40 }
    static var maxKeyframes: Int { 28 }
    static var maxChunks: Int { 700 }
    static var keyframeMaxWidth: Int { 360 }
    static var liveVertexSoftCap: Int { 32_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        if vCount > 45_000 { return 3 }
        if vCount > 22_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if faceCount > 30_000 { return 3 }
        if faceCount > 15_000 { return 2 }
        return 1
    }

    // Done quality
    static var finalVertexSoftCap: Int { highDetail ? 200_000 : 130_000 }
    static var triangleBudget: Int { highDetail ? 240_000 : 150_000 }
    static var bakeKeyframeLimit: Int { 28 }
    static var samplesPerTriangle: Int { 4 }
    static var quantizeShift: Int { 3 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 4_000 { return 10 }
        if faceCount > 1_500 { return 7 }
        return 5
    }
}
