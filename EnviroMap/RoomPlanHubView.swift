import SwiftUI

/// Room Plan hub: start LiDAR scan, open Room Planner (blank or from saved room).
struct RoomPlanHubView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var showScanner = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    // 1) Instant planner (works offline / simulator)
                    NavigationLink {
                        RoomPlannerView(session: nil)
                    } label: {
                        primaryCard(
                            title: "Open Room Planner",
                            subtitle: "Empty room · furniture catalog · drag & arrange",
                            icon: "square.grid.3x3.topleft.filled",
                            gradient: true
                        )
                    }
                    .buttonStyle(.plain)

                    // 2) LiDAR scan
                    Button {
                        showScanner = true
                    } label: {
                        primaryCard(
                            title: "Scan real room (LiDAR)",
                            subtitle: "Capture mesh on a Pro iPhone, then design it",
                            icon: "camera.viewfinder",
                            gradient: false
                        )
                    }
                    .buttonStyle(.plain)

                    if store.sessions.isEmpty {
                        emptyHint
                    } else {
                        savedSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Room Plan")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showScanner) {
            ScanFlowView()
                .environmentObject(store)
        }
        .onChange(of: showScanner) { _, open in
            if !open { store.loadIndex() }
        }
    }

    private var background: some View {
        ZStack {
            AppTheme.bg
            LinearGradient(
                colors: [
                    AppTheme.blue.opacity(0.12),
                    AppTheme.blueSoft.opacity(0.4),
                    AppTheme.bg,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan any space")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.text)
            Text("Start with a blank room or a LiDAR scan. Add furniture, drag to arrange, reopen anytime.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primaryCard(title: String, subtitle: String, icon: String, gradient: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(gradient ? Color.white.opacity(0.2) : AppTheme.blueSoft)
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(gradient ? .white : AppTheme.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .opacity(gradient ? 0.9 : 1)
                    .foregroundStyle(gradient ? Color.white : AppTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
        }
        .foregroundStyle(gradient ? .white : AppTheme.text)
        .padding(16)
        .background {
            if gradient {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.blue, AppTheme.blueDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: AppTheme.blue.opacity(0.35), radius: 16, y: 8)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            step("1", "Open Room Planner and place furniture now")
            step("2", "Or scan a real room on a LiDAR iPhone")
            step("3", "Open that scan later to design on its walls")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    private func step(_ n: String, _ t: String) -> some View {
        HStack(spacing: 12) {
            Text(n)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppTheme.blue, in: Circle())
            Text(t)
                .font(.subheadline)
                .foregroundStyle(AppTheme.text)
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Design a scanned room")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            ForEach(store.sessions) { session in
                NavigationLink {
                    RoomPlannerView(session: session)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.blueSoft)
                                .frame(width: 52, height: 52)
                            Image(systemName: "cube.transparent.fill")
                                .foregroundStyle(AppTheme.blue)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.name)
                                .font(.headline)
                                .foregroundStyle(AppTheme.text)
                            Text("\(session.wallCount) walls · Plan with furniture")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Text("Plan")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.blueSoft, in: Capsule())
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppTheme.cardBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
