import Foundation

/// Central mesh / color density for Full 3D Scan.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    // MARK: Live capture — prioritize coverage (cars need dense anchors)

    static var meshCopyInterval: TimeInterval { highDetail ? 0.09 : 0.14 }
    static var keyframeInterval: TimeInterval { highDetail ? 0.09 : 0.13 }
    static var maxKeyframes: Int { highDetail ? 110 : 72 }
    static var maxChunks: Int { highDetail ? 3200 : 2000 }
    static var keyframeMaxWidth: Int { highDetail ? 640 : 480 }
    static var liveVertexSoftCap: Int { highDetail ? 150_000 : 100_000 }

    static func liveVertexStep(vCount: Int) -> Int {
        // Prefer density during live scan — only thin extreme anchors
        if highDetail { return vCount > 140_000 ? 2 : 1 }
        return vCount > 90_000 ? 2 : 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if highDetail { return faceCount > 100_000 ? 2 : 1 }
        return faceCount > 60_000 ? 2 : 1
    }

    // MARK: Bake / Review

    static var triangleBudget: Int { highDetail ? 260_000 : 160_000 }
    static var bakeKeyframeLimit: Int { highDetail ? 40 : 28 }
    static var samplesPerTriangle: Int { highDetail ? 5 : 4 }
    static var quantizeShift: Int { highDetail ? 2 : 3 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 14_000 { return 4 }
        if faceCount > 6_000 { return 3 }
        if faceCount > 2_500 { return 2 }
        return 1
    }
}
