import SwiftUI

// MARK: - Root
// Flow: Onboarding (first launch) → MainHub (Tools + Library)

struct RootView: View {
    @EnvironmentObject private var store: SessionStore

    // New key so intro shows even if you ran an older build
    @AppStorage("enviromap.onboarding.completed.v2") private var onboardingCompleted = false

    var body: some View {
        Group {
            if onboardingCompleted {
                // MAIN APP — tools grid + library (all new features)
                MainHubView()
            } else {
                // INTRO SCREENS (no paywall)
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        onboardingCompleted = true
                    }
                }
            }
        }
        .preferredColorScheme(onboardingCompleted ? .light : .dark)
        .tint(AppTheme.blue)
    }
}

#Preview {
    RootView()
        .environmentObject(SessionStore())
}
