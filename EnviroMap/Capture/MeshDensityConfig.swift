import Foundation

/// Mesh / color density for Full 3D Scan.
/// Tuned so live scanning stays smooth (no freezes) while Review stays detailed.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    // MARK: Live capture — smooth first (freeze = failed scan)

    /// Mesh snapshot rate (seconds). Slightly slower = far more stable.
    static var meshCopyInterval: TimeInterval { highDetail ? 0.20 : 0.28 }

    /// RGB keyframe rate. YUV convert is expensive — keep modest.
    static var keyframeInterval: TimeInterval { highDetail ? 0.22 : 0.30 }

    /// Fewer frames in RAM = less memory pressure / freezes.
    static var maxKeyframes: Int { highDetail ? 48 : 32 }

    static var maxChunks: Int { highDetail ? 1800 : 1200 }

    /// Smaller live RGB = big FPS win; bake still looks good.
    static var keyframeMaxWidth: Int { highDetail ? 480 : 360 }

    static var liveVertexSoftCap: Int { highDetail ? 80_000 : 50_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        if highDetail {
            if vCount > 80_000 { return 3 }
            if vCount > 40_000 { return 2 }
            return 1
        }
        if vCount > 50_000 { return 3 }
        if vCount > 25_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if highDetail {
            if faceCount > 60_000 { return 3 }
            if faceCount > 30_000 { return 2 }
            return 1
        }
        if faceCount > 40_000 { return 3 }
        if faceCount > 20_000 { return 2 }
        return 1
    }

    // MARK: Final harvest (Done) — full quality, not during live

    static var finalVertexSoftCap: Int { highDetail ? 200_000 : 120_000 }

    // MARK: Bake / Review

    static var triangleBudget: Int { highDetail ? 200_000 : 120_000 }
    static var bakeKeyframeLimit: Int { highDetail ? 32 : 22 }
    static var samplesPerTriangle: Int { highDetail ? 4 : 3 }
    static var quantizeShift: Int { highDetail ? 2 : 3 }

    /// Blue wire is visual only — keep cheap.
    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 8_000 { return 6 }
        if faceCount > 3_000 { return 4 }
        if faceCount > 1_200 { return 3 }
        return 2
    }
}
