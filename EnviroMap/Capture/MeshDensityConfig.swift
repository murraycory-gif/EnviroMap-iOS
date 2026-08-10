import Foundation

/// Dense coverage + clear color indoors & outdoors (dark/bright adaptive).
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    /// Color frames: denser while moving for clearer paint
    static func keyframeInterval(movingFast: Bool) -> TimeInterval {
        movingFast ? 0.08 : 0.12
    }

    static var maxKeyframes: Int { 110 }
    static var maxChunks: Int { 9000 }
    /// Higher res keyframes = clearer surfaces
    static var keyframeMaxWidth: Int { 1152 }

    static var liveMeshCopyUntilChunks: Int { 0 }
    static var meshCopyInterval: TimeInterval { 999 }
    static var postWarmupMeshInterval: TimeInterval { 999 }

    static func liveVertexStep(vCount: Int) -> Int { 1 }
    static func liveFaceStep(faceCount: Int) -> Int { 1 }

    static var finalVertexSoftCap: Int { 2_500_000 }
    /// More triangles kept = denser coverage / fewer holes
    static var triangleBudget: Int { highDetail ? 750_000 : 450_000 }
    static var bakeKeyframeLimit: Int { 80 }
    static var samplesPerTriangle: Int { 1 }
    static var quantizeShift: Int { 2 }

    /// Live mesh bank: how often / how many tiles (safe, sync copy)
    static var meshBankInterval: TimeInterval { 0.40 }
    static var meshBankTilesPerTick: Int { 48 }

    /// Depth hole-fill sample density (lower step = denser)
    static var depthSampleStep: Int { 4 }
    static var depthIngestInterval: TimeInterval { 0.35 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        faceCount > 4_000 ? 10 : 5
    }
}
