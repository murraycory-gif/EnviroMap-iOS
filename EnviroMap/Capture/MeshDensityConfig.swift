import Foundation

/// CAPTURE-FIRST: never drop whole objects. Live stays light; Done harvests full mesh.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    // MARK: Live — frequent mesh, light color, smooth

    static var meshCopyInterval: TimeInterval { 0.20 }  // more mesh updates = better coverage
    static var keyframeInterval: TimeInterval { 0.35 }
    static var maxKeyframes: Int { 32 }
    static var maxChunks: Int { 1500 }  // keep many tiles (cars = many anchors)
    static var keyframeMaxWidth: Int { 400 }

    /// Soft target for live subsample — NEVER discard the whole anchor
    static var liveVertexTarget: Int { 48_000 }
    static var liveFaceTarget: Int { 60_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        // Subsample only; keep every anchor
        if vCount > 120_000 { return 4 }
        if vCount > 80_000 { return 3 }
        if vCount > 48_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if faceCount > 100_000 { return 4 }
        if faceCount > 60_000 { return 3 }
        if faceCount > 40_000 { return 2 }
        return 1
    }

    // MARK: Done harvest — full power

    static var finalVertexSoftCap: Int { 400_000 }  // only skip insane anchors
    static var triangleBudget: Int { highDetail ? 320_000 : 200_000 }
    static var bakeKeyframeLimit: Int { 32 }
    static var samplesPerTriangle: Int { 4 }
    static var quantizeShift: Int { 3 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 5_000 { return 8 }
        if faceCount > 2_000 { return 5 }
        return 3
    }
}
