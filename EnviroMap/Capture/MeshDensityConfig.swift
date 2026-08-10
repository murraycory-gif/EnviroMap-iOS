import Foundation

/// Central mesh / color density knobs for Full 3D Scan.
/// High Detail = denser mesh + sharper colors (slightly slower bake).
/// Balanced = smooth live scan + solid Review quality.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    // MARK: Live capture

    /// How often we copy LiDAR mesh anchors while scanning (seconds).
    static var meshCopyInterval: TimeInterval { highDetail ? 0.12 : 0.18 }

    /// How often we grab RGB keyframes (seconds).
    static var keyframeInterval: TimeInterval { highDetail ? 0.10 : 0.15 }

    /// Max stored camera frames for color bake.
    static var maxKeyframes: Int { highDetail ? 96 : 64 }

    /// Max mesh chunks retained during scan.
    static var maxChunks: Int { highDetail ? 2500 : 1600 }

    /// RGB downscale width for keyframes.
    static var keyframeMaxWidth: Int { highDetail ? 720 : 560 }

    /// Soft vertex cap per anchor during live copy (final harvest always denser).
    static var liveVertexSoftCap: Int { highDetail ? 120_000 : 80_000 }

    // MARK: Live subsample (performance only — final harvest uses fullQuality)

    static func liveVertexStep(vCount: Int) -> Int {
        if highDetail {
            return vCount > 100_000 ? 2 : 1
        }
        return vCount > 60_000 ? 2 : 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if highDetail {
            return faceCount > 80_000 ? 2 : 1
        }
        return faceCount > 45_000 ? 2 : 1
    }

    // MARK: Bake / Review

    /// Max triangles colored into the final SceneKit mesh.
    static var triangleBudget: Int { highDetail ? 220_000 : 140_000 }

    /// How many keyframes used when painting colors.
    static var bakeKeyframeLimit: Int { highDetail ? 36 : 24 }

    /// Color samples per triangle (centroid + verts).
    static var samplesPerTriangle: Int { highDetail ? 5 : 4 }

    /// Quantize bits per channel for material grouping (higher = more color steps).
    static var quantizeShift: Int { highDetail ? 2 : 3 } // 6-bit vs 5-bit

    /// Blue wireframe face step for live overlay (visual only).
    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 12_000 { return 4 }
        if faceCount > 5_000 { return 3 }
        if faceCount > 2_000 { return 2 }
        return 1
    }
}
