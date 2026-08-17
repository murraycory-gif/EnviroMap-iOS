import SwiftUI
import CoreMotion
import UIKit

/// Level — same light blue Home theme. Real top bar so Back is tappable.
struct LevelToolView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var motion = LevelMotion()

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                Spacer(minLength: 8)

                levelHUD(diameter: 280)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 8)

                VStack(spacing: 12) {
                    Text(String(format: "%.0f°", motion.primaryDeg))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(motion.isLevel ? levelGreen : AppTheme.text)
                        .contentTransition(.numericText())

                    Text(motion.isLevel ? "Level" : motion.hint)
                        .font(.subheadline.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(motion.isLevel ? levelGreen : AppTheme.textSecondary)

                    HStack(spacing: 10) {
                        metricCard(motion.axisAName, motion.axisADeg)
                        metricCard(motion.axisBName, motion.axisBDeg)
                    }
                    .padding(.horizontal, 20)

                    Text(motion.instruction)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 8)
                }
                .padding(.bottom, 16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.light)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.blueSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            modeChips
                .frame(maxWidth: .infinity)
        }
    }

    private var levelGreen: Color {
        Color(red: 0.10, green: 0.62, blue: 0.42)
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
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(mode.label)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(on ? Color.white : AppTheme.blue)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            Capsule().fill(on ? AppTheme.blue : AppTheme.card)
        }
        .overlay(
            Capsule().stroke(on ? Color.clear : AppTheme.cardBorder, lineWidth: 1)
        )
        .shadow(color: on ? AppTheme.blue.opacity(0.25) : .clear, radius: 6, y: 2)
    }

    private func metricCard(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(String(format: "%+.1f°", value))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppTheme.blue.opacity(0.06), radius: 8, y: 3)
    }

    private func levelHUD(diameter: CGFloat) -> some View {
        let scale = diameter / 280
        return ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: diameter, height: diameter)
                .shadow(color: AppTheme.blue.opacity(0.12), radius: 20, y: 8)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.blue, Color(red: 0.35, green: 0.65, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(2.5, 3 * scale)
                )
                .frame(width: diameter * 0.92, height: diameter * 0.92)

            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(AppTheme.blue.opacity(i % 3 == 0 ? 0.45 : 0.18))
                    .frame(width: (i % 3 == 0 ? 3 : 1.5) * scale, height: (i % 3 == 0 ? 12 : 7) * scale)
                    .offset(y: -diameter * 0.41)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            Circle()
                .stroke(AppTheme.blue.opacity(0.18), lineWidth: 1)
                .frame(width: diameter * 0.30, height: diameter * 0.30)

            Path { p in
                let c = diameter / 2
                let arm = diameter * 0.34
                p.move(to: CGPoint(x: c - arm, y: c))
                p.addLine(to: CGPoint(x: c + arm, y: c))
                p.move(to: CGPoint(x: c, y: c - arm))
                p.addLine(to: CGPoint(x: c, y: c + arm))
            }
            .stroke(AppTheme.blue.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
            .frame(width: diameter, height: diameter)

            Circle()
                .stroke(motion.isLevel ? levelGreen : AppTheme.blue.opacity(0.7), lineWidth: 2)
                .frame(width: 26 * scale, height: 26 * scale)

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
            .shadow(color: AppTheme.blue.opacity(0.45), radius: 10, y: 2)
            .offset(x: motion.offsetX * scale, y: motion.offsetY * scale)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetX)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.82), value: motion.offsetY)

            if motion.isLevel {
                Circle()
                    .stroke(levelGreen.opacity(0.75), lineWidth: 3)
                    .frame(width: diameter * 0.95, height: diameter * 0.95)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var background: some View {
        ZStack {
            AppTheme.bg
            LinearGradient(
                colors: [
                    AppTheme.blue.opacity(0.12),
                    AppTheme.blueSoft.opacity(0.45),
                    AppTheme.bg,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            if motion.isLevel {
                RadialGradient(
                    colors: [levelGreen.opacity(0.16), .clear],
                    center: .center,
                    startRadius: 40,
                    endRadius: 360
                )
            }
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
    @Published var hint: String = "Center The Bubble"
    @Published var instruction: String = "Lay Flat, Stand Upright, Or Tilt On Its Side."
    @Published var modeTitle: String = "Surface level"

    private let manager = CMMotionManager()
    private let maxOffset: CGFloat = 95
    private var wasLevel = false
    private let mapRange: Double = 20
    private let levelThreshold: Double = 1.0

    func start() {
        guard manager.isDeviceMotionAvailable else {
            hint = "Motion Unavailable"
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
