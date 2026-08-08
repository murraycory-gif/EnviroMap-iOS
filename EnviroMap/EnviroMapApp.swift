import SwiftUI
import UIKit

@main
struct EnviroMapApp: App {
    @StateObject private var store = SessionStore()

    private let launchDarkUI = UIColor(red: 0.06, green: 0.10, blue: 0.22, alpha: 1)
    private let launchDark = Color(red: 0.06, green: 0.10, blue: 0.22)

    init() {
        // No white UIWindow flash between system launch and first frame
        UIWindow.appearance().backgroundColor = launchDarkUI
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                launchDark.ignoresSafeArea()
                RootView()
                    .environmentObject(store)
            }
            .background(launchDark.ignoresSafeArea())
            .onAppear {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .forEach { $0.backgroundColor = launchDarkUI }
            }
        }
    }
}
