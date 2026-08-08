import SwiftUI
import CoreMotion
import UIKit

/// Multi-orientation digital level — flat · upright · side.
/// Look is EnviroMap (blue rings / HUD), not Apple Measure green-screen.
struct LevelToolView: View {
    @StateObject private var motion = LevelMotion()

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Mode pill
                HStack(spacing: 8) {
                    modeChip(.flat, icon: "rectangle.landscape.rotate")
                    modeChip(.upright, icon: "iphone")
                    modeChip(.side, icon: "iphone.landscape")
                }
                .padding(.top, 12)
                .padding(.bottom, 8)

                Text(motion.modeTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer(minLength: 8)

                // Primary angle
                Text(String(format: "%.0f°", motion.primaryDeg))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(motion.isLevel ? Color(red: 0.15, green: 0.85, blue: 0.55) : .white)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.12), value: motion.primaryDeg)

                Text(motion.isLevel ? "LEVEL" : motion.hint)
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(motion.isLevel ? Color(red: 0.15, green: 0.85, blue: 0.55) : .white.opacity(0.7))
                    .padding(.top, 4)

                Spacer(minLength: 12)

                // HUD
                levelHUD
                    .frame(width: 280, height: 280)

                Spacer(minLength: 16)

                // Dual readouts
                HStack(spacing: 12) {
                    readout(title: motion.axisAName, value: motion.axisADeg)
                    readout(title: motion.axisBName, value: motion.axisBDeg)
                }
                .padding(.horizontal, 20)

                Text(motion.instruction)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle("Level")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    // MARK: HUD — ring + crosshair + bubble (not Apple green fill)

    private var levelHUD: some View {
        ZStack {
            // Outer ring
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
                    lineWidth: 3
                )
                .frame(width: 260, height: 260)

            // Tick marks
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i % 3 == 0 ? 0.45 : 0.18))
                    .frame(width: i % 3 == 0 ? 3 : 2, height: i % 3 == 0 ? 14 : 8)
                    .offset(y: -118)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            // Inner target ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                .frame(width: 88, height: 88)

            // Crosshair
            Path { p in
                p.move(to: CGPoint(x: 140 - 100, y: 140))
                p.addLine(to: CGPoint(x: 140 + 100, y: 140))
                p.move(to: CGPoint(x: 140, y: 140 - 100))
                p.addLine(to: CGPoint(x: 140, y: 140 + 100))
            }
            .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
            .frame(width: 280, height: 280)

            // Center bullseye
            Circle()
                .stroke(motion.isLevel ? Color(red: 0.15, green: 0.85, blue: 0.55) : AppTheme.blue, lineWidth: 2)
                .frame(width: 28, height: 28)

            // Bubble (glass orb)
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
                            endRadius: 20
                        )
                    )
                Circle()
                    .fill(.white.opacity(0.45))
                    .frame(width: 10, height: 6)
                    .offset(x: -4, y: -6)
            }
            .frame(width: 40, height: 40)
            .shadow(color: AppTheme.blue.opacity(0.55), radius: 10, y: 2)
            .offset(x: motion.offsetX, y: motion.offsetY)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetX)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetY)

            // Level flash ring
            if motion.isLevel {
                Circle()
                    .stroke(Color(red: 0.15, green: 0.85, blue: 0.55).opacity(0.7), lineWidth: 4)
                    .frame(width: 268, height: 268)
                    .transition(.opacity)
            }
        }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.12)
            // Soft blue ambient — not Apple green wash
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
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(mode.label)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(on ? .white : .white.opacity(0.45))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(String(format: "%+.1f°", value))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    /// Degrees from level for bubble mapping (±)
    private let mapRange: Double = 20
    /// Snap-to-level threshold
    private let levelThreshold: Double = 1.0

    var modeTitleLive: String { modeTitle }

    func start() {
        guard manager.isDeviceMotionAvailable else {
            hint = "Motion unavailable"
            return
        }
        // Reference frame that follows the device screen
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
        // Gravity: points toward Earth in device coords
        // x = right, y = top of device, z = out of screen (toward user when face-up)
        let gx = data.gravity.x
        let gy = data.gravity.y
        let gz = data.gravity.z

        let ax = abs(gx)
        let ay = abs(gy)
        let az = abs(gz)

        // Dominant gravity axis → orientation mode
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
            // Face-up / face-down on a table — true surface level
            // Perfect flat: gx≈0, gy≈0, |gz|≈1
            let degX = asin(clamp(gx, -1, 1)) * 180 / .pi
            let degY = asin(clamp(gy, -1, 1)) * 180 / .pi
            axisAName = "Left–Right"
            axisBName = "Front–Back"
            axisADeg = degX
            axisBDeg = degY
            primaryDeg = hypot(degX, degY)
            offsetX = mapToOffset(degX)
            offsetY = mapToOffset(-degY) // match screen Y
            isLevel = abs(degX) < levelThreshold && abs(degY) < levelThreshold
            hint = isLevel ? "LEVEL" : "Tilt until bubble centers"
            instruction = "Lay the phone flat on a counter, shelf, or floor."
            modeTitle = "Flat · surface"

        case .upright:
            // Portrait against a wall — plumb line (vertical)
            // Perfect upright: gx≈0, |gy|≈1, gz≈0
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
            // Landscape — phone on long edge
            // Perfect side: |gx|≈1, gy≈0, gz≈0
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
            instruction = "Turn the phone on its side (landscape) on a ledge or frame."
            modeTitle = "Side · landscape edge"
        }

        // Haptic when we snap into level
        if isLevel && !wasLevel {
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.success)
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
