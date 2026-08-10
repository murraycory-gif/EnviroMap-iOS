import Foundation

/// High clarity bake; live scan stays stable.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    static var meshCopyInterval: TimeInterval { highDetail ? 0.15 : 0.22 }
    static var keyframeInterval: TimeInterval { highDetail ? 0.14 : 0.22 }
    static var maxKeyframes: Int { highDetail ? 72 : 48 }
    static var maxChunks: Int { highDetail ? 2800 : 1800 }
    /// Photo resolution for sharp textures (3D Snap–beating clarity)
    static var keyframeMaxWidth: Int { highDetail ? 960 : 640 }
    static var liveVertexSoftCap: Int { highDetail ? 110_000 : 70_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        if highDetail { return vCount > 90_000 ? 2 : 1 }
        return vCount > 50_000 ? 2 : 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if highDetail { return faceCount > 60_000 ? 2 : 1 }
        return faceCount > 40_000 ? 2 : 1
    }

    static var finalVertexSoftCap: Int { highDetail ? 280_000 : 180_000 }
    static var triangleBudget: Int { highDetail ? 350_000 : 200_000 }
    static var bakeKeyframeLimit: Int { highDetail ? 56 : 36 }
    static var samplesPerTriangle: Int { highDetail ? 5 : 4 }
    static var quantizeShift: Int { highDetail ? 2 : 3 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 10_000 { return 5 }
        if faceCount > 4_000 { return 4 }
        if faceCount > 1_500 { return 3 }
        return 2
    }
}
