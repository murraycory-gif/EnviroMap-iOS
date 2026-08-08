import SwiftUI
import UIKit

// MARK: - Root
// System launch = solid dark (no logo image — avoids white checkerboard).
// Then our splash: dark blue + transparent logo + EnviroMap name.

struct RootView: View {
    @EnvironmentObject private var store: SessionStore

    @AppStorage("enviromap.onboarding.completed.v2") private var onboardingCompleted = false
    @State private var showSplash = true

    private let launchDark = Color(red: 0.06, green: 0.10, blue: 0.22)

    var body: some View {
        ZStack {
            launchDark.ignoresSafeArea()

            if showSplash {
                LaunchSplashView()
                    .zIndex(2)
            } else if onboardingCompleted {
                MainHubView()
                    .transition(.opacity)
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
                withAnimation(.easeInOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Splash (what you liked): dark blue + logo + name under

struct LaunchSplashView: View {
    private let markName = "EnviroMapMark"

    @State private var appear = false

    var body: some View {
        ZStack {
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
                .frame(width: 160, height: 160)
                .shadow(color: AppTheme.blue.opacity(0.4), radius: 24, y: 10)
                .scaleEffect(appear ? 1 : 0.9)
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
