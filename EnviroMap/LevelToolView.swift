import SwiftUI
import CoreMotion

/// Digital surface level using CoreMotion.
struct LevelToolView: View {
    @StateObject private var motion = LevelMotion()

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            VStack(spacing: 28) {
                Text(motion.isLevel ? "Level" : "Tilt to center")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(motion.isLevel ? Color.green : AppTheme.text)

                ZStack {
                    Circle()
                        .stroke(AppTheme.cardBorder, lineWidth: 2)
                        .frame(width: 240, height: 240)
                    Circle()
                        .stroke(AppTheme.blue.opacity(0.25), lineWidth: 1)
                        .frame(width: 120, height: 120)
                    Circle()
                        .fill(AppTheme.blue.opacity(0.15))
                        .frame(width: 16, height: 16)

                    // Bubble
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white, AppTheme.blue],
                                center: .center,
                                startRadius: 2,
                                endRadius: 18
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: AppTheme.blue.opacity(0.4), radius: 8)
                        .offset(x: motion.offsetX, y: motion.offsetY)
                        .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: motion.offsetX)
                }
                .frame(width: 260, height: 260)
                .background(
                    Circle()
                        .fill(AppTheme.card)
                        .shadow(color: .black.opacity(0.06), radius: 20, y: 8)
                )

                HStack(spacing: 24) {
                    metric(title: "Pitch", value: String(format: "%.1f°", motion.pitchDeg))
                    metric(title: "Roll", value: String(format: "%.1f°", motion.rollDeg))
                }

                Text("Lay the phone flat on a surface, or hold upright against a wall.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .padding(.top, 40)
        }
        .navigationTitle("Level")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.text)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
    }
}

@MainActor
final class LevelMotion: ObservableObject {
    @Published var pitchDeg: Double = 0
    @Published var rollDeg: Double = 0
    @Published var offsetX: CGFloat = 0
    @Published var offsetY: CGFloat = 0
    @Published var isLevel = false

    private let manager = CMMotionManager()
    private let maxOffset: CGFloat = 90

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let pitch = data.attitude.pitch * 180 / .pi
            let roll = data.attitude.roll * 180 / .pi
            self.pitchDeg = pitch
            self.rollDeg = roll
            // Map degrees to bubble offset (clamped)
            self.offsetX = CGFloat(max(-25, min(25, roll))) / 25 * self.maxOffset
            self.offsetY = CGFloat(max(-25, min(25, pitch))) / 25 * self.maxOffset
            self.isLevel = abs(pitch) < 1.2 && abs(roll) < 1.2
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
