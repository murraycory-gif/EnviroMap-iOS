import Foundation

/// Walk-speed capture · O-style sharp color · AF-style reliable harvest.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    /// Color often enough at walking speed, not every frame
    static func keyframeInterval(movingFast: Bool) -> TimeInterval {
        movingFast ? 0.09 : 0.14
    }

    static var maxKeyframes: Int { 96 }
    static var maxChunks: Int { 12_000 }

    static var liveKeyframeMaxWidth: Int { 800 }
    static var keyframeMaxWidth: Int { 800 }

    static var liveMeshCopyUntilChunks: Int { 0 }
    static var meshCopyInterval: TimeInterval { 999 }
    static var postWarmupMeshInterval: TimeInterval { 999 }

    static func liveVertexStep(vCount: Int) -> Int { 1 }
    static func liveFaceStep(faceCount: Int) -> Int { 1 }

    static var finalVertexSoftCap: Int { 3_500_000 }
    static var triangleBudget: Int { highDetail ? 1_200_000 : 700_000 }
    static var bakeKeyframeLimit: Int { 40 }
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
