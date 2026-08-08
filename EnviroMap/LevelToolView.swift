import SwiftUI
import CoreMotion
import UIKit

/// Full-screen modern level — no system nav bar.
/// HUD dead-center; data as clean floating glass.
struct LevelToolView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var motion = LevelMotion()

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                background.ignoresSafeArea()

                // Centered HUD (true screen center)
                levelHUD(diameter: hudDiameter(size: geo.size, landscape: isLandscape))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Floating chrome
                if isLandscape {
                    landscapeChrome(size: geo.size, safe: geo.safeAreaInsets)
                } else {
                    portraitChrome(size: geo.size, safe: geo.safeAreaInsets)
                }

                // Back — top left only (no grey bar)
                backButton
                    .position(
                        x: max(geo.safeAreaInsets.leading, 16) + 28,
                        y: max(geo.safeAreaInsets.top, 16) + 28
                    )
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private func hudDiameter(size: CGSize, landscape: Bool) -> CGFloat {
        if landscape {
            return min(size.height * 0.72, size.width * 0.40, 300)
        }
        return min(size.width * 0.78, size.height * 0.42, 300)
    }

    // MARK: - Back

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        // Keep full hit target clear of screen edge / Dynamic Island
        .padding(4)
    }

    // MARK: - Portrait chrome (around center HUD)

    private func portraitChrome(size: CGSize, safe: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            // Top: modes centered under safe area
            modeChips
                .padding(.top, safe.top + 64)

            Spacer()

            // Bottom stack under HUD
            VStack(spacing: 14) {
                Text(String(format: "%.0f°", motion.primaryDeg))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(levelColor)
                    .contentTransition(.numericText())

                Text(motion.isLevel ? "Level" : motion.hint)
                    .font(.subheadline.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(motion.isLevel ? levelColor : .white.opacity(0.65))

                HStack(spacing: 10) {
                    metricCard(motion.axisAName, motion.axisADeg)
                    metricCard(motion.axisBName, motion.axisBDeg)
                }
                .padding(.horizontal, 24)

                Text(motion.instruction)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, max(safe.bottom, 16) + 20)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Landscape chrome

    private func landscapeChrome(size: CGSize, safe: EdgeInsets) -> some View {
        ZStack {
            // Left data column — angle + metrics only
            HStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(format: "%.0f°", motion.primaryDeg))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(levelColor)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(motion.isLevel ? "Level" : motion.hint)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(motion.isLevel ? levelColor : .white.opacity(0.7))

                    VStack(spacing: 10) {
                        metricCard(motion.axisAName, motion.axisADeg)
                        metricCard(motion.axisBName, motion.axisBDeg)
                    }
                    .frame(maxWidth: 200)
                }
                .padding(.leading, max(safe.leading, 20) + 64)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .center)

                Spacer()
            }

            // Mode chips — vertical on the right
            HStack {
                Spacer()
                modeChipsVertical
                    .padding(.trailing, max(safe.trailing, 20) + 8)
            }

            // Instruction — centered bottom of screen
            VStack {
                Spacer()
                Text(motion.instruction)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: size.width * 0.7)
                    .padding(.bottom, max(safe.bottom, 12) + 14)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Flat / Upright / Side stacked down the right edge
    private var modeChipsVertical: some View {
        VStack(spacing: 10) {
            modeChip(.flat, icon: "rectangle.landscape.rotate")
            modeChip(.upright, icon: "iphone")
            modeChip(.side, icon: "iphone.landscape")
        }
    }

    // MARK: - Pieces

    private var levelColor: Color {
        motion.isLevel ? Color(red: 0.2, green: 0.9, blue: 0.6) : .white
    }

    private var modeChips: some View {
        HStack(spacing: 6) {
            modeChip(.flat, icon: "rectangle.landscape.rotate")
            modeChip(.upright, icon: "iphone")
            modeChip(.side, icon: "iphone.landscape")
        }
    }

    private func modeChip(_ mode: LevelMotion.Mode, icon: String) -> some View {
        let on = motion.mode == mode
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .frame(width: 16)
            Text(mode.label)
                .font(.caption.weight(.bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(on ? .white : .white.opacity(0.55))
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(width: 118, alignment: .leading)
        .background {
            if on {
                Capsule().fill(AppTheme.blue)
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .overlay(
            Capsule().stroke(Color.white.opacity(on ? 0 : 0.1), lineWidth: 1)
        )
    }

    private func metricCard(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(String(format: "%+.1f°", value))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func levelHUD(diameter: CGFloat) -> some View {
        let scale = diameter / 280
        return ZStack {
            // Soft plate behind ring
            Circle()
                .fill(Color.white.opacity(0.03))
                .frame(width: diameter, height: diameter)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            AppTheme.blue.opacity(0.95),
                            Color(red: 0.35, green: 0.75, blue: 1.0).opacity(0.45),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(2.5, 3 * scale)
                )
                .frame(width: diameter * 0.92, height: diameter * 0.92)

            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i % 3 == 0 ? 0.45 : 0.16))
                    .frame(width: (i % 3 == 0 ? 3 : 1.5) * scale, height: (i % 3 == 0 ? 12 : 7) * scale)
                    .offset(y: -diameter * 0.41)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: diameter * 0.30, height: diameter * 0.30)

            Path { p in
                let c = diameter / 2
                let arm = diameter * 0.34
                p.move(to: CGPoint(x: c - arm, y: c))
                p.addLine(to: CGPoint(x: c + arm, y: c))
                p.move(to: CGPoint(x: c, y: c - arm))
                p.addLine(to: CGPoint(x: c, y: c + arm))
            }
            .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
            .frame(width: diameter, height: diameter)

            Circle()
                .stroke(motion.isLevel ? levelColor : AppTheme.blue.opacity(0.8), lineWidth: 2)
                .frame(width: 26 * scale, height: 26 * scale)

            // Bubble
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.95),
                                AppTheme.blue.opacity(0.85),
                                AppTheme.blueDeep.opacity(0.95),
                            ],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 1,
                            endRadius: 18 * scale
                        )
                    )
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 9 * scale, height: 5 * scale)
                    .offset(x: -3 * scale, y: -5 * scale)
            }
            .frame(width: 38 * scale, height: 38 * scale)
            .shadow(color: AppTheme.blue.opacity(0.5), radius: 12, y: 2)
            .offset(x: motion.offsetX * scale, y: motion.offsetY * scale)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetX)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetY)

            if motion.isLevel {
                Circle()
                    .stroke(levelColor.opacity(0.7), lineWidth: 3)
                    .frame(width: diameter * 0.95, height: diameter * 0.95)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var background: some View {
        ZStack {
            Color(red: 0.03, green: 0.05, blue: 0.10)
            RadialGradient(
                colors: [
                    motion.isLevel
                        ? Color(red: 0.08, green: 0.4, blue: 0.3).opacity(0.4)
                        : AppTheme.blue.opacity(0.22),
                    .clear,
                ],
                center: .center,
                startRadius: 40,
                endRadius: 380
            )
        }
        .animation(.easeInOut(duration: 0.3), value: motion.isLevel)
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
            hint = isLevel ? "Level" : "Tilt Until Bubble Centers"
            instruction = "Lay The Phone Flat On A Counter, Shelf, Or Floor."
            modeTitle = "Flat · Surface"

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
            hint = isLevel ? "Level" : "Align To Vertical"
            instruction = "Hold Upright Against A Wall Or Post."
            modeTitle = "Upright · Plumb"

        case .side:
            let degAlong = asin(clamp(gy, -1, 1)) * 180 / .pi
            let degLean = asin(clamp(gz, -1, 1)) * 180 / .pi
            axisAName = "Along Edge"
            axisBName = "Lean"
            axisADeg = degAlong
            axisBDeg = degLean
            primaryDeg = hypot(degAlong, degLean)
            offsetX = mapToOffset(degAlong)
            offsetY = mapToOffset(degLean)
            isLevel = abs(degAlong) < levelThreshold && abs(degLean) < levelThreshold
            hint = isLevel ? "Level" : "Align On Its Side"
            instruction = "Rest On The Long Edge — Center The Bubble."
            modeTitle = "Side · Edge"
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
