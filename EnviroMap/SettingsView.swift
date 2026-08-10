import SwiftUI

/// EnviroMap Settings — dark blue glass style (distinct from 3D Snap purple).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("enviromap.ai.improveTools") private var improveAI = true
    @AppStorage("enviromap.scan.showBlueMesh") private var showBlueMesh = true
    @AppStorage("enviromap.scan.highDetail") private var highDetail = true
    @AppStorage("enviromap.scan.aiCoach") private var aiCoach = true

    var body: some View {
        NavigationStack {
            ZStack {
                // EnviroMap navy gradient (not competitor purple)
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.08, blue: 0.16),
                        Color(red: 0.08, green: 0.12, blue: 0.22),
                        Color(red: 0.04, green: 0.06, blue: 0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        // AI hero card
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [AppTheme.blue, AppTheme.blueDeep],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "sparkles")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("EnviroMap AI")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.white)
                                    Text("Smarter scans · cleaner maps")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                                Spacer()
                                Toggle("", isOn: $improveAI)
                                    .labelsHidden()
                                    .tint(AppTheme.blue)
                            }

                            Text("When on, AI coaches your scan, classifies surfaces (floor, wall, furniture), and boosts color blending for clearer 3D maps.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(AppTheme.blue.opacity(0.35), lineWidth: 1)
                                )
                        )

                        sectionHeader("Scan Quality")
                        settingsCard {
                            toggleRow(
                                icon: "lines.measurement.horizontal",
                                title: "Blue Mapping Mesh",
                                subtitle: "Live wireframe while scanning",
                                isOn: $showBlueMesh
                            )
                            Divider().overlay(Color.white.opacity(0.08))
                            toggleRow(
                                icon: "square.3.layers.3d.top.filled",
                                title: "High Mesh Density",
                                subtitle: "Max triangles + sharper real colors (cars, rooms). Slightly longer bake.",
                                isOn: $highDetail
                            )
                            Divider().overlay(Color.white.opacity(0.08))
                            toggleRow(
                                icon: "brain.head.profile",
                                title: "AI Scan Coach",
                                subtitle: "Live tips to fill holes",
                                isOn: $aiCoach
                            )
                        }

                        sectionHeader("General")
                        settingsCard {
                            linkRow(icon: "arrow.clockwise", title: "Restore Purchases") {
                                // No IAP yet — placeholder
                            }
                            Divider().overlay(Color.white.opacity(0.08))
                            linkRow(icon: "star.fill", title: "Rate EnviroMap") {
                                if let url = URL(string: "https://apps.apple.com") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            Divider().overlay(Color.white.opacity(0.08))
                            ShareLink(item: URL(string: "https://enviromap.app") ?? URL(string: "https://x.com")!) {
                                HStack(spacing: 14) {
                                    Image(systemName: "square.and.arrow.up")
                                        .frame(width: 22)
                                        .foregroundStyle(AppTheme.blue)
                                    Text("Share App")
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                                .padding(.vertical, 12)
                            }
                            Divider().overlay(Color.white.opacity(0.08))
                            linkRow(icon: "envelope.fill", title: "Contact Us") {
                                if let url = URL(string: "mailto:hello@enviromap.app") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            Divider().overlay(Color.white.opacity(0.08))
                            linkRow(icon: "sparkle.magnifyingglass", title: "Explore Features") {}
                        }

                        sectionHeader("Legal")
                        settingsCard {
                            linkRow(icon: "hand.raised.fill", title: "Privacy Policy") {}
                            Divider().overlay(Color.white.opacity(0.08))
                            linkRow(icon: "doc.text.fill", title: "Terms Of Use") {}
                        }

                        // Brand footer
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "cube.transparent.fill")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.blue)
                                Text("EnviroMap")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08), in: Capsule())

                            Text("Version \(appVersion)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.leading, 4)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func toggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(AppTheme.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.blue)
        }
        .padding(.vertical, 12)
    }

    private func linkRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundStyle(AppTheme.blue)
                Text(title)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
