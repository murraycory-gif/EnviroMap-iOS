import Foundation

/// Live scan smooth; bake uses higher photo res for clarity.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    static var meshCopyInterval: TimeInterval { highDetail ? 0.16 : 0.24 }
    static var keyframeInterval: TimeInterval { highDetail ? 0.16 : 0.24 }
    static var maxKeyframes: Int { highDetail ? 64 : 40 }
    static var maxChunks: Int { highDetail ? 2400 : 1500 }
    /// Higher = sharper photo textures (3D Snap clarity)
    static var keyframeMaxWidth: Int { highDetail ? 720 : 520 }
    static var liveVertexSoftCap: Int { highDetail ? 100_000 : 60_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        if highDetail { return vCount > 80_000 ? 2 : 1 }
        return vCount > 45_000 ? 2 : 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if highDetail { return faceCount > 55_000 ? 2 : 1 }
        return faceCount > 35_000 ? 2 : 1
    }

    static var finalVertexSoftCap: Int { highDetail ? 240_000 : 150_000 }
    static var triangleBudget: Int { highDetail ? 280_000 : 160_000 }
    static var bakeKeyframeLimit: Int { highDetail ? 48 : 30 }
    static var samplesPerTriangle: Int { highDetail ? 4 : 3 }
    static var quantizeShift: Int { highDetail ? 2 : 3 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 10_000 { return 5 }
        if faceCount > 4_000 { return 4 }
        if faceCount > 1_500 { return 3 }
        return 2
    }
}
