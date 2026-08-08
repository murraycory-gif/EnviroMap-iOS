import SwiftUI
import UIKit

// MARK: - Root
// Flow: Splash (logo + name) → Onboarding (first launch) → MainHub
// Never flash white — dark base always under content.

struct RootView: View {
    @EnvironmentObject private var store: SessionStore

    @AppStorage("enviromap.onboarding.completed.v2") private var onboardingCompleted = false
    @State private var showSplash = true

    private let launchDark = Color(red: 0.06, green: 0.10, blue: 0.22)

    var body: some View {
        ZStack {
            // Permanent dark base (prevents white frame)
            launchDark.ignoresSafeArea()

            if showSplash {
                LaunchSplashView()
                    .zIndex(2)
            } else if onboardingCompleted {
                MainHubView()
                    .transition(.opacity)
                    .preferredColorScheme(.light)
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        onboardingCompleted = true
                    }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(showSplash || !onboardingCompleted ? .dark : .light)
        .tint(AppTheme.blue)
        .background(launchDark.ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeInOut(duration: 0.45)) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Launch splash (big logo + name underneath)

struct LaunchSplashView: View {
    private let markName = "EnviroMapMark"

    @State private var appear = false

    var body: some View {
        ZStack {
            // Same dark as system launch screen — seamless handoff
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.10, blue: 0.22),
                    Color(red: 0.10, green: 0.18, blue: 0.42),
                    Color(red: 0.05, green: 0.08, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.blue.opacity(0.28))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(y: -40)

            Circle()
                .fill(Color(red: 0.3, green: 0.55, blue: 1.0).opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 50)
                .offset(x: 80, y: 180)

            VStack(spacing: 22) {
                Group {
                    if let ui = UIImage(named: markName)?.withRenderingMode(.alwaysOriginal) {
                        Image(uiImage: ui)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else if let ui = UIImage(named: "EnviroMapLogo")?.withRenderingMode(.alwaysOriginal) {
                        Image(uiImage: ui)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.blue, AppTheme.blueDeep],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Image(systemName: "cube.transparent.fill")
                                .font(.system(size: 72, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 168, height: 168)
                .shadow(color: AppTheme.blue.opacity(0.45), radius: 28, y: 12)
                .scaleEffect(appear ? 1 : 0.92)
                .opacity(appear ? 1 : 0.85)

                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Text("Enviro")
                            .foregroundStyle(.white)
                        Text("Map")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.55, green: 0.78, blue: 1.0),
                                        Color(red: 0.35, green: 0.62, blue: 1.0),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .tracking(-1.2)

                    Text("Map · Measure · Design")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .opacity(appear ? 1 : 0.9)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appear = true
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SessionStore())
}
