import SwiftUI
import CoreMotion
import UIKit

/// Multi-orientation digital level — flat · upright · side.
/// Layout adapts for landscape so nothing is clipped at the top.
struct LevelToolView: View {
    @StateObject private var motion = LevelMotion()

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            ZStack {
                background.ignoresSafeArea()

                if isLandscape {
                    landscapeBody(size: geo.size, safeTop: safeTop, safeBottom: safeBottom)
                } else {
                    portraitBody(safeTop: safeTop)
                }
            }
        }
        .navigationTitle("Level")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar) // free space when phone is on its side
        .preferredColorScheme(.dark)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    // MARK: - Portrait (full vertical stack)

    private func portraitBody(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            modeChips
                .padding(.top, 8)

            Text(motion.modeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 6)

            Spacer(minLength: 6)

            primaryAngle
            statusLine
                .padding(.top, 4)

            Spacer(minLength: 8)

            levelHUD(diameter: 260)

            Spacer(minLength: 12)

            dualReadouts
                .padding(.horizontal, 20)

            Text(motion.instruction)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Landscape (sideways phone) — content fits, no top cutoff

    private func landscapeBody(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Left column: modes + angle + readouts
            VStack(spacing: 8) {
                modeChips
                    .scaleEffect(0.92)

                Text(motion.modeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                primaryAngle
                    .scaleEffect(0.85)

                statusLine

                dualReadouts
                    .frame(maxWidth: 280)

                Text(motion.instruction)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: size.width * 0.42)
            .padding(.leading, 8)

            // Right: HUD scaled to height
            let hudSize = min(size.height - safeTop - safeBottom - 24, size.width * 0.48, 240)
            levelHUD(diameter: hudSize)
                .frame(width: hudSize, height: hudSize)
                .padding(.trailing, 12)
        }
        .padding(.top, max(safeTop * 0.15, 4))
        .padding(.bottom, max(safeBottom, 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Shared pieces

    private var modeChips: some View {
        HStack(spacing: 6) {
            modeChip(.flat, icon: "rectangle.landscape.rotate")
            modeChip(.upright, icon: "iphone")
            modeChip(.side, icon: "iphone.landscape")
        }
    }

    private var primaryAngle: some View {
        Text(String(format: "%.0f°", motion.primaryDeg))
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(motion.isLevel ? Color(red: 0.15, green: 0.85, blue: 0.55) : .white)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.12), value: motion.primaryDeg)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var statusLine: some View {
        Text(motion.isLevel ? "LEVEL" : motion.hint)
            .font(.caption.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(motion.isLevel ? Color(red: 0.15, green: 0.85, blue: 0.55) : .white.opacity(0.7))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var dualReadouts: some View {
        HStack(spacing: 10) {
            readout(title: motion.axisAName, value: motion.axisADeg)
            readout(title: motion.axisBName, value: motion.axisBDeg)
        }
    }

    private func levelHUD(diameter: CGFloat) -> some View {
        let scale = diameter / 280
        return ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            AppTheme.blue.opacity(0.9),
                            Color(red: 0.3, green: 0.75, blue: 1.0).opacity(0.5),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3 * scale
                )
                .frame(width: diameter * 0.93, height: diameter * 0.93)

            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i % 3 == 0 ? 0.45 : 0.18))
                    .frame(width: (i % 3 == 0 ? 3 : 2) * scale, height: (i % 3 == 0 ? 12 : 7) * scale)
                    .offset(y: -diameter * 0.42)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                .frame(width: diameter * 0.31, height: diameter * 0.31)

            // Crosshair
            Path { p in
                let c = diameter / 2
                let arm = diameter * 0.36
                p.move(to: CGPoint(x: c - arm, y: c))
                p.addLine(to: CGPoint(x: c + arm, y: c))
                p.move(to: CGPoint(x: c, y: c - arm))
                p.addLine(to: CGPoint(x: c, y: c + arm))
            }
            .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
            .frame(width: diameter, height: diameter)

            Circle()
                .stroke(motion.isLevel ? Color(red: 0.15, green: 0.85, blue: 0.55) : AppTheme.blue, lineWidth: 2)
                .frame(width: 28 * scale, height: 28 * scale)

            // Bubble — scale offset with HUD size
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.95),
                                AppTheme.blue.opacity(0.85),
                                AppTheme.blueDeep.opacity(0.9),
                            ],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 1,
                            endRadius: 18 * scale
                        )
                    )
                Circle()
                    .fill(.white.opacity(0.45))
                    .frame(width: 9 * scale, height: 5 * scale)
                    .offset(x: -3 * scale, y: -5 * scale)
            }
            .frame(width: 36 * scale, height: 36 * scale)
            .shadow(color: AppTheme.blue.opacity(0.55), radius: 8, y: 2)
            .offset(x: motion.offsetX * scale, y: motion.offsetY * scale)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetX)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetY)

            if motion.isLevel {
                Circle()
                    .stroke(Color(red: 0.15, green: 0.85, blue: 0.55).opacity(0.7), lineWidth: 3.5)
                    .frame(width: diameter * 0.96, height: diameter * 0.96)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var background: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.12)
            RadialGradient(
                colors: [
                    motion.isLevel
                        ? Color(red: 0.1, green: 0.45, blue: 0.35).opacity(0.45)
                        : AppTheme.blue.opacity(0.28),
                    .clear,
                ],
                center: .center,
                startRadius: 20,
                endRadius: 320
            )
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.10, blue: 0.22),
                    Color(red: 0.03, green: 0.04, blue: 0.09),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.85)
        }
        .animation(.easeInOut(duration: 0.25), value: motion.isLevel)
    }

    private func modeChip(_ mode: LevelMotion.Mode, icon: String) -> some View {
        let on = motion.mode == mode
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(mode.label)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(on ? .white : .white.opacity(0.45))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(on ? AppTheme.blue.opacity(0.85) : Color.white.opacity(0.08))
        )
        .overlay(
            Capsule()
                .stroke(on ? AppTheme.blue : Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func readout(title: String, value: Double) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(String(format: "%+.1f°", value))
                .font(.body.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Motion (flat / upright / side)

@MainActor
final class LevelMotion: ObservableObject {
    enum Mode: Equatable {
        case flat, upright, side

        var label: String {
            switch self {
            case .flat: return "Flat"
            case .upright: return "Upright"
            case .side: return "Side"
            }
        }
    }

    @Published var mode: Mode = .flat
    @Published var primaryDeg: Double = 0
    @Published var axisADeg: Double = 0
    @Published var axisBDeg: Double = 0
    @Published var axisAName: String = "X"
    @Published var axisBName: String = "Y"
    @Published var offsetX: CGFloat = 0
    @Published var offsetY: CGFloat = 0
    @Published var isLevel = false
    @Published var hint: String = "Center the bubble"
    @Published var instruction: String = "Lay flat, stand upright, or tilt on its side."
    @Published var modeTitle: String = "Surface level"

    private let manager = CMMotionManager()
    private let maxOffset: CGFloat = 95
    private var wasLevel = false
    private let mapRange: Double = 20
    private let levelThreshold: Double = 1.0

    func start() {
        guard manager.isDeviceMotionAvailable else {
            hint = "Motion unavailable"
            return
        }
        manager.deviceMotionUpdateInterval = 1.0 / 45.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.process(data)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func process(_ data: CMDeviceMotion) {
        let gx = data.gravity.x
        let gy = data.gravity.y
        let gz = data.gravity.z

        let ax = abs(gx)
        let ay = abs(gy)
        let az = abs(gz)

        let newMode: Mode
        if az >= ax && az >= ay {
            newMode = .flat
        } else if ay >= ax {
            newMode = .upright
        } else {
            newMode = .side
        }
        mode = newMode

        switch newMode {
        case .flat:
            let degX = asin(clamp(gx, -1, 1)) * 180 / .pi
            let degY = asin(clamp(gy, -1, 1)) * 180 / .pi
            axisAName = "Left–Right"
            axisBName = "Front–Back"
            axisADeg = degX
            axisBDeg = degY
            primaryDeg = hypot(degX, degY)
            offsetX = mapToOffset(degX)
            offsetY = mapToOffset(-degY)
            isLevel = abs(degX) < levelThreshold && abs(degY) < levelThreshold
            hint = isLevel ? "LEVEL" : "Tilt until bubble centers"
            instruction = "Lay the phone flat on a counter, shelf, or floor."
            modeTitle = "Flat · surface"

        case .upright:
            let degSide = asin(clamp(gx, -1, 1)) * 180 / .pi
            let degLean = asin(clamp(gz, -1, 1)) * 180 / .pi
            axisAName = "Left–Right"
            axisBName = "Lean"
            axisADeg = degSide
            axisBDeg = degLean
            primaryDeg = hypot(degSide, degLean)
            offsetX = mapToOffset(degSide)
            offsetY = mapToOffset(degLean)
            isLevel = abs(degSide) < levelThreshold && abs(degLean) < levelThreshold
            hint = isLevel ? "PLUMB" : "Align to vertical"
            instruction = "Hold upright against a wall or post (portrait)."
            modeTitle = "Upright · wall / plumb"

        case .side:
            let degAlong = asin(clamp(gy, -1, 1)) * 180 / .pi
            let degLean = asin(clamp(gz, -1, 1)) * 180 / .pi
            axisAName = "Along edge"
            axisBName = "Lean"
            axisADeg = degAlong
            axisBDeg = degLean
            primaryDeg = hypot(degAlong, degLean)
            offsetX = mapToOffset(degAlong)
            offsetY = mapToOffset(degLean)
            isLevel = abs(degAlong) < levelThreshold && abs(degLean) < levelThreshold
            hint = isLevel ? "LEVEL" : "Align on its side"
            instruction = "Phone on its side — align bubble to center."
            modeTitle = "Side · landscape edge"
        }

        if isLevel && !wasLevel {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        wasLevel = isLevel
    }

    private func mapToOffset(_ degrees: Double) -> CGFloat {
        let t = clamp(degrees / mapRange, -1, 1)
        return CGFloat(t) * maxOffset
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }
}
