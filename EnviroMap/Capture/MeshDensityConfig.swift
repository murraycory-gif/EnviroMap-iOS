import Foundation

/// Coverage from BL/BN · sharper photos for clarity.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    static func keyframeInterval(movingFast: Bool) -> TimeInterval {
        movingFast ? 0.42 : 0.60
    }

    static var maxKeyframes: Int { 64 }
    static var maxChunks: Int { 12_000 }

    static var liveKeyframeMaxWidth: Int { 960 }
    static var sharpKeyframeMaxWidth: Int { 1280 }
    static var keyframeMaxWidth: Int { 1600 }

    static var liveMeshCopyUntilChunks: Int { 0 }
    static var meshCopyInterval: TimeInterval { 999 }
    static var postWarmupMeshInterval: TimeInterval { 999 }

    static func liveVertexStep(vCount: Int) -> Int { 1 }
    static func liveFaceStep(faceCount: Int) -> Int { 1 }

    static var finalVertexSoftCap: Int { 3_500_000 }
    static var triangleBudget: Int { highDetail ? 1_400_000 : 800_000 }
    static var bakeKeyframeLimit: Int { 56 }
    static var samplesPerTriangle: Int { 1 }
    static var quantizeShift: Int { 2 }

    static var meshBankInterval: TimeInterval { 999 }
    static var meshBankTilesPerTick: Int { 32 }

    static var depthSampleStep: Int { 4 }
    static var depthIngestInterval: TimeInterval { 0.55 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        faceCount > 4_000 ? 12 : 6
    }
}
