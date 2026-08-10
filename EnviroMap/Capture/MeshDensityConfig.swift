import Foundation

/// Scan light (smooth) · Finish heavy (max coverage + clear color).
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    /// Color while walking — not every frame (lag)
    static func keyframeInterval(movingFast: Bool) -> TimeInterval {
        movingFast ? 0.12 : 0.18
    }

    static var maxKeyframes: Int { 64 }
    static var maxChunks: Int { 12_000 }

    /// Live scan uses this (smaller = smoother)
    static var liveKeyframeMaxWidth: Int { 720 }
    /// Finish harvest / bake uses this (clearer)
    static var keyframeMaxWidth: Int { 1280 }

    static var liveMeshCopyUntilChunks: Int { 0 }
    static var meshCopyInterval: TimeInterval { 999 }
    static var postWarmupMeshInterval: TimeInterval { 999 }

    static func liveVertexStep(vCount: Int) -> Int { 1 }
    static func liveFaceStep(faceCount: Int) -> Int { 1 }

    static var finalVertexSoftCap: Int { 3_500_000 }
    static var triangleBudget: Int { highDetail ? 1_400_000 : 800_000 }
    static var bakeKeyframeLimit: Int { 96 }
    static var samplesPerTriangle: Int { 1 }
    static var quantizeShift: Int { 2 }

    /// Rare full bank sweep during walk (smooth)
    static var meshBankInterval: TimeInterval { 999 }
    static var meshBankTilesPerTick: Int { 32 }

    static var depthSampleStep: Int { 4 }
    static var depthIngestInterval: TimeInterval { 0.55 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        faceCount > 4_000 ? 12 : 6
    }
}
