import SwiftUI
import UIKit

@main
struct EnviroMapApp: App {
    @StateObject private var store = SessionStore()

    init() {
        // Kill default white window / nav chrome flash before first SwiftUI frame
        let dark = UIColor(red: 0.06, green: 0.10, blue: 0.22, alpha: 1)
        UIWindow.appearance().backgroundColor = dark
        UIView.appearance().backgroundColor = .clear
        UIScrollView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Always paint dark first — never white under RootView
                Color(red: 0.06, green: 0.10, blue: 0.22)
                    .ignoresSafeArea()

                RootView()
                    .environmentObject(store)
            }
            .preferredColorScheme(.dark) // until RootView overrides after splash
            .background(Color(red: 0.06, green: 0.10, blue: 0.22).ignoresSafeArea())
            .onAppear {
                // Belt-and-suspenders: tint live key window
                let dark = UIColor(red: 0.06, green: 0.10, blue: 0.22, alpha: 1)
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .forEach { $0.backgroundColor = dark }
            }
        }
    }
}
