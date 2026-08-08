import SwiftUI
import CoreMotion
import UIKit

/// Multi-orientation digital level — flat · upright · side.
/// Landscape: big HUD center · data left · mode chips top-right.
struct LevelToolView: View {
    @StateObject private var motion = LevelMotion()

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                background.ignoresSafeArea()

                if isLandscape {
                    landscapeBody(size: geo.size, safe: geo.safeAreaInsets)
                } else {
                    portraitBody()
                }
            }
        }
        .navigationTitle("Level")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    // MARK: - Portrait

    private func portraitBody() -> some View {
        VStack(spacing: 0) {
            modeChips
                .padding(.top, 10)

            Text(motion.modeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 8)

            Spacer(minLength: 8)

            primaryAngle(size: 72)
            statusLine
                .padding(.top, 6)

            Spacer(minLength: 12)

            levelHUD(diameter: 280)

            Spacer(minLength: 16)

            dualReadouts(compact: false)
                .padding(.horizontal, 20)

            Text(motion.instruction)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Landscape
    // Left = data (roomy) · Center = large HUD · Top-right = mode chips

    private func landscapeBody(size: CGSize, safe: EdgeInsets) -> some View {
        let availableH = size.height - safe.top - safe.bottom
        // HUD: dominate the center — use most of height
        let hudSize = min(availableH * 0.88, size.width * 0.42, 340)

        return ZStack(alignment: .topTrailing) {
            // Mode chips — top right (under nav, clear of back button)
            modeChips
                .padding(.top, 6)
                .padding(.trailing, max(safe.trailing, 16))

            HStack(alignment: .center, spacing: 0) {
                // LEFT — data column (generous)
                VStack(alignment: .leading, spacing: 14) {
                    Spacer(minLength: 0)

                    Text(motion.modeTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    primaryAngle(size: 80)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    statusLine
                        .frame(maxWidth: .infinity, alignment: .leading)

                    dualReadouts(compact: false)
                        .frame(maxWidth: 320)

                    Text(motion.instruction)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    Spacer(minLength: 0)
                }
                .frame(width: size.width * 0.36, alignment: .leading)
                .padding(.leading, max(safe.leading, 20))
                .padding(.trailing, 12)
                .padding(.vertical, 12)

                // CENTER — big level HUD
                levelHUD(diameter: hudSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // RIGHT spacer so HUD stays truly centered vs left column weight
                Color.clear
                    .frame(width: size.width * 0.12)
                    .padding(.trailing, max(safe.trailing, 8))
            }
            .padding(.top, 36) // room for chips row
            .padding(.bottom, max(safe.bottom, 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Shared

    private var modeChips: some View {
        HStack(spacing: 8) {
            modeChip(.flat, icon: "rectangle.landscape.rotate")
            modeChip(.upright, icon: "iphone")
            modeChip(.side, icon: "iphone.landscape")
        }
    }

    private func primaryAngle(size: CGFloat) -> some View {
        Text(String(format: "%.0f°", motion.primaryDeg))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(motion.isLevel ? Color(red: 0.15, green: 0.85, blue: 0.55) : .white)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.12), value: motion.primaryDeg)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var statusLine: some View {
        Text(motion.isLevel ? "LEVEL" : motion.hint)
            .font(.body.weight(.bold))
            .tracking(1.0)
            .foregroundStyle(motion.isLevel ? Color(red: 0.15, green: 0.85, blue: 0.55) : .white.opacity(0.75))
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }

    private func dualReadouts(compact: Bool) -> some View {
        HStack(spacing: 12) {
            readout(title: motion.axisAName, value: motion.axisADeg, compact: compact)
            readout(title: motion.axisBName, value: motion.axisBDeg, compact: compact)
        }
    }

    private func levelHUD(diameter: CGFloat) -> some View {
        let scale = diameter / 280
        return ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            AppTheme.blue.opacity(0.95),
                            Color(red: 0.3, green: 0.75, blue: 1.0).opacity(0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(3, 3.5 * scale)
                )
                .frame(width: diameter * 0.93, height: diameter * 0.93)

            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i % 3 == 0 ? 0.5 : 0.2))
                    .frame(width: (i % 3 == 0 ? 3.5 : 2) * scale, height: (i % 3 == 0 ? 14 : 8) * scale)
                    .offset(y: -diameter * 0.42)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                .frame(width: diameter * 0.32, height: diameter * 0.32)

            Path { p in
                let c = diameter / 2
                let arm = diameter * 0.36
                p.move(to: CGPoint(x: c - arm, y: c))
                p.addLine(to: CGPoint(x: c + arm, y: c))
                p.move(to: CGPoint(x: c, y: c - arm))
                p.addLine(to: CGPoint(x: c, y: c + arm))
            }
            .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.2, dash: [5, 6]))
            .frame(width: diameter, height: diameter)

            Circle()
                .stroke(motion.isLevel ? Color(red: 0.15, green: 0.85, blue: 0.55) : AppTheme.blue, lineWidth: 2.5)
                .frame(width: max(28, 32 * scale), height: max(28, 32 * scale))

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
                            endRadius: 20 * scale
                        )
                    )
                Circle()
                    .fill(.white.opacity(0.45))
                    .frame(width: 10 * scale, height: 6 * scale)
                    .offset(x: -4 * scale, y: -6 * scale)
            }
            .frame(width: max(40, 44 * scale), height: max(40, 44 * scale))
            .shadow(color: AppTheme.blue.opacity(0.55), radius: 12, y: 2)
            .offset(x: motion.offsetX * scale, y: motion.offsetY * scale)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetX)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetY)

            if motion.isLevel {
                Circle()
                    .stroke(Color(red: 0.15, green: 0.85, blue: 0.55).opacity(0.75), lineWidth: 4)
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
                endRadius: 340
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
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(mode.label)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(on ? .white : .white.opacity(0.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(on ? AppTheme.blue.opacity(0.9) : Color.white.opacity(0.1))
        )
        .overlay(
            Capsule()
                .stroke(on ? AppTheme.blue : Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func readout(title: String, value: Double, compact: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(String(format: "%+.1f°", value))
                .font(compact ? .title3.weight(.bold).monospacedDigit() : .title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 10 : 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

// MARK: - Motion

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

        let ax = abs(gx), ay = abs(gy), az = abs(gz)

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
        CGFloat(clamp(degrees / mapRange, -1, 1)) * maxOffset
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }
}
