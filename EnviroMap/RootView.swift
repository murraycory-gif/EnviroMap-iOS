import SwiftUI

// MARK: - Root
// System launch screen shows dark + logo (Info.plist).
// App opens straight into Onboarding or MainHub — no second splash / no white frame.

struct RootView: View {
    @EnvironmentObject private var store: SessionStore

    @AppStorage("enviromap.onboarding.completed.v2") private var onboardingCompleted = false

    private let launchDark = Color(red: 0.06, green: 0.10, blue: 0.22)

    var body: some View {
        ZStack {
            // Match system launch color until content paints
            launchDark.ignoresSafeArea()

            if onboardingCompleted {
                MainHubView()
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        onboardingCompleted = true
                    }
                }
            }
        }
        .preferredColorScheme(onboardingCompleted ? .light : .dark)
        .tint(AppTheme.blue)
        .background(launchDark.ignoresSafeArea())
    }
}

#Preview {
    RootView()
        .environmentObject(SessionStore())
}
