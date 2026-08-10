import Foundation

/// Capture more surfaces; vertex-color bake with real camera colors.
enum MeshDensityConfig {
    static var highDetail: Bool {
        UserDefaults.standard.object(forKey: "enviromap.scan.highDetail") as? Bool ?? true
    }

    // Live — more mesh, stable color frames
    static var meshCopyInterval: TimeInterval { 0.14 }
    static var keyframeInterval: TimeInterval { 0.22 }
    static var maxKeyframes: Int { 48 }
    static var maxChunks: Int { 2200 }
    static var keyframeMaxWidth: Int { 640 }

    static func liveVertexStep(vCount: Int) -> Int {
        if vCount > 120_000 { return 3 }
        if vCount > 60_000 { return 2 }
        return 1
    }

    static func liveFaceStep(faceCount: Int) -> Int {
        if faceCount > 100_000 { return 3 }
        if faceCount > 50_000 { return 2 }
        return 1
    }

    static var finalVertexSoftCap: Int { 500_000 }
    static var triangleBudget: Int { highDetail ? 360_000 : 220_000 }
    static var bakeKeyframeLimit: Int { 48 }
    static var samplesPerTriangle: Int { 5 }
    static var quantizeShift: Int { 2 }

    static func blueWireFaceStep(faceCount: Int) -> Int {
        if faceCount > 5_000 { return 8 }
        if faceCount > 2_000 { return 5 }
        return 3
    }
}
