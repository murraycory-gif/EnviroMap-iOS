import SwiftUI
import UIKit

private let kBrandAssetName = "EnviroMapMark"
private let kBrandAssetIsFullLockup = false

struct LibraryView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()

                if store.sessions.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BrandHeader(height: 32)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.blue)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.9), in: Circle())
                            .shadow(color: AppTheme.blue.opacity(0.12), radius: 8, y: 2)
                    }
                    .accessibilityLabel("New scan")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: RoomSession.self) { session in
                SessionDetailView(session: session)
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScanFlowView()
                    .environmentObject(store)
            }
            .onChange(of: showScanner) { _, open in
                if !open {
                    store.loadIndex()
                }
            }
        }
    }

    private var background: some View {
        ZStack {
            AppTheme.bg
            LinearGradient(
                colors: [
                    AppTheme.blue.opacity(0.12),
                    AppTheme.blueSoft.opacity(0.5),
                    AppTheme.bg,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            BrandHeader(height: 64)
            Text("No rooms yet")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.text)
            Text("Scan with LiDAR, or open Room Planner to design a blank space first.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            NavigationLink {
                RoomPlannerView(session: nil)
            } label: {
                Label("Open Room Planner", systemImage: "square.grid.3x3.topleft.filled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)

            Button {
                showScanner = true
            } label: {
                Label("Scan environment", systemImage: "camera.viewfinder")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
            }
            Spacer()
        }
    }

    private var listContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                Button {
                    showScanner = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.blue, AppTheme.blueDeep],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                            Image(systemName: "plus")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan new environment")
                                .font(.headline)
                                .foregroundStyle(AppTheme.text)
                            Text("LiDAR Room Plan")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(16)
                    .background(cardBackground)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RoomPlannerView(session: nil)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.blueSoft)
                                .frame(width: 52, height: 52)
                            Image(systemName: "square.grid.3x3.topleft.filled")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Room Planner")
                                .font(.headline)
                                .foregroundStyle(AppTheme.text)
                            Text("Blank room + furniture catalog")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(16)
                    .background(cardBackground)
                }
                .buttonStyle(.plain)

                HStack {
                    Text("Saved on this iPhone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Text("\(store.sessions.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.blueSoft, in: Capsule())
                }
                .padding(.top, 8)

                ForEach(store.sessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(session)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
            .fill(AppTheme.card)
            .shadow(color: AppTheme.blue.opacity(0.06), radius: 12, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
    }
}

// MARK: - Brand header

struct BrandHeader: View {
    var height: CGFloat = 56

    private var markUIImage: UIImage? {
        UIImage(named: kBrandAssetName)?.withRenderingMode(.alwaysOriginal)
    }

    var body: some View {
        Group {
            if let ui = markUIImage {
                if kBrandAssetIsFullLockup {
                    Image(uiImage: ui)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: height)
                        .frame(maxWidth: height * 5.5)
                } else {
                    HStack(spacing: height * 0.22) {
                        Image(uiImage: ui)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: height, height: height)
                            .shadow(color: AppTheme.blue.opacity(0.22), radius: height * 0.12, y: height * 0.06)

                        HStack(spacing: 0) {
                            Text("Enviro")
                                .foregroundStyle(AppTheme.text)
                            Text("Map")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            AppTheme.blue,
                                            Color(red: 0.35, green: 0.65, blue: 1.0),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .font(.system(size: height * 0.58, weight: .bold, design: .rounded))
                        .tracking(-1.0)
                    }
                }
            } else {
                EnviroMapLogo(showWordmark: true, height: height)
            }
        }
        .accessibilityLabel("EnviroMap")
    }
}

// MARK: - Rows

struct SessionRow: View {
    @EnvironmentObject private var store: SessionStore
    let session: RoomSession

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                Text(session.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                Text("\(session.wallCount) walls · \(session.objectCount) objects")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                .fill(AppTheme.card)
                .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        let url = store.thumbnailURL(for: session)
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppTheme.blueSoft)
            .frame(width: 60, height: 60)
            .overlay {
                if let url, let ui = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if let mark = UIImage(named: kBrandAssetName) {
                    Image(uiImage: mark)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    Image(systemName: "cube.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.blue)
                }
            }
            .clipped()
    }
}

// MARK: - Session detail

/// Value-based routes — nested NavigationLink(destination:) breaks inside navigationDestination.
enum SessionAction: String, Hashable {
    case planner
    case floorPlan
    case mesh
    case walkAR
}

struct SessionDetailView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    let session: RoomSession

    @State private var showRename = false
    @State private var draftName = ""
    @State private var showShare = false
    @State private var toast: String?

    private var live: RoomSession {
        store.sessions.first(where: { $0.id == session.id }) ?? session
    }

    private var usdzExists: Bool {
        FileManager.default.fileExists(atPath: store.usdzURL(for: live).path)
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard
                    statsRow
                    actionsSection
                    manageSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(live.name)
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.blue)
        .navigationDestination(for: SessionAction.self) { action in
            switch action {
            case .planner:
                RoomPlannerView(session: live)
            case .floorPlan:
                FloorPlanView(session: live)
            case .mesh:
                RoomViewerView(session: live)
            case .walkAR:
                ARWalkView(usdzURL: store.usdzURL(for: live))
            }
        }
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $draftName)
            Button("Save") {
                store.rename(live, to: draftName)
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: store.shareItems(for: live))
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppTheme.blueDeep))
                    .padding(.top, 8)
            }
        }
    }

    private var background: some View {
        ZStack {
            AppTheme.bg
            LinearGradient(
                colors: [
                    AppTheme.blue.opacity(0.14),
                    AppTheme.blueSoft.opacity(0.45),
                    AppTheme.bg,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(AppTheme.blue.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 40)
                .offset(x: 100, y: -120)
        }
    }

    private var heroCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.blue, AppTheme.blueDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: "cube.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(live.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
                Text(live.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                statusChip(usdzExists ? "USDZ ready" : "No mesh file", ok: usdzExists)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.card.opacity(0.95))
                .shadow(color: AppTheme.blue.opacity(0.08), radius: 16, y: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    private func statusChip(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(ok ? AppTheme.blue : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((ok ? AppTheme.blueSoft : Color.orange.opacity(0.15)), in: Capsule())
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile("Walls", "\(live.wallCount)", "square.split.2x1")
            statTile("Objects", "\(live.objectCount)", "shippingbox")
            statTile("Doors", "\(live.doorCount)", "door.left.hand.open")
            statTile("Windows", "\(live.windowCount)", "window.horizontal")
        }
    }

    private func statTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.blue)
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(AppTheme.text)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            actionLink(
                title: "Room Planner",
                subtitle: "Place furniture on this room",
                icon: "square.grid.3x3.topleft.filled",
                action: .planner
            )
            actionLink(
                title: "Floor plan",
                subtitle: "2D walls from LiDAR scan",
                icon: "square.split.bottomrightquarter",
                action: .floorPlan
            )
            actionLink(
                title: "View 3D mesh",
                subtitle: usdzExists ? "Orbit the USDZ model" : "Mesh file missing",
                icon: "cube.transparent",
                action: .mesh,
                disabled: !usdzExists
            )
            actionLink(
                title: "Walk in AR",
                subtitle: usdzExists ? "Place mesh in real space" : "Mesh file missing",
                icon: "figure.walk",
                action: .walkAR,
                disabled: !usdzExists
            )
        }
    }

    private func actionLink(
        title: String,
        subtitle: String,
        icon: String,
        action: SessionAction,
        disabled: Bool = false
    ) -> some View {
        Group {
            if disabled {
                Button {
                    flash("USDZ not found — rescan this room")
                } label: {
                    actionRowLabel(title: title, subtitle: subtitle, icon: icon, chevron: false)
                        .opacity(0.55)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: action) {
                    actionRowLabel(title: title, subtitle: subtitle, icon: icon, chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionRowLabel(title: String, subtitle: String, icon: String, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.blueSoft)
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
                .shadow(color: AppTheme.blue.opacity(0.05), radius: 10, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            Button {
                draftName = live.name
                showRename = true
            } label: {
                manageRow("Rename", icon: "pencil", color: AppTheme.blue)
            }
            .buttonStyle(.plain)

            Button {
                if usdzExists {
                    showShare = true
                } else {
                    flash("Nothing to export yet")
                }
            } label: {
                manageRow("Export USDZ", icon: "square.and.arrow.up", color: AppTheme.blue)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                store.delete(live)
                dismiss()
            } label: {
                manageRow("Delete scan", icon: "trash", color: .red)
            }
            .buttonStyle(.plain)
        }
    }

    private func manageRow(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(color == .red ? Color.red : AppTheme.text)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    private func flash(_ msg: String) {
        withAnimation { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { toast = nil }
        }
    }
}
