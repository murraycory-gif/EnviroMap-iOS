import SwiftUI
import UIKit

// MARK: - Root
// Flow (first install):
//   1) Light system launch (same as Home)
//   2) Splash — big logo + EnviroMap name
//   3) Onboarding intro pages
//   4) Main hub
// Returning users skip 3 after they finish intro once.

struct RootView: View {
    @EnvironmentObject private var store: SessionStore

    @AppStorage("enviromap.onboarding.completed.v3") private var onboardingCompleted = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            if showSplash {
                LaunchSplashView()
                    .zIndex(3)
            } else if !onboardingCompleted {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        onboardingCompleted = true
                    }
                }
                .transition(.opacity)
                .zIndex(2)
            } else {
                MainHubView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(showSplash || onboardingCompleted ? .light : .dark)
        .tint(AppTheme.blue)
        .background(AppTheme.bg.ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Splash (Home light theme, large logo)

struct LaunchSplashView: View {
    private let markName = "EnviroMapMark"

    @State private var appear = false

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()
            LinearGradient(
                colors: [
                    AppTheme.blue.opacity(0.14),
                    AppTheme.blueSoft.opacity(0.55),
                    AppTheme.bg,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.blue.opacity(0.16))
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(y: -20)

            VStack(spacing: 28) {
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
                            RoundedRectangle(cornerRadius: 48, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.blue, AppTheme.blueDeep],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Image(systemName: "cube.transparent.fill")
                                .font(.system(size: 120, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 280, height: 280)
                .shadow(color: AppTheme.blue.opacity(0.28), radius: 28, y: 12)
                .scaleEffect(appear ? 1 : 0.92)
                .opacity(appear ? 1 : 0.9)

                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Text("Enviro")
                            .foregroundStyle(AppTheme.text)
                        Text("Map")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.blue, AppTheme.blueDeep],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .tracking(-1.2)

                    Text("Map · Measure · Design")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
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
