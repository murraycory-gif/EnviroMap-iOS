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
                    AppTheme.blue.opacity(0.10),
                    AppTheme.bg,
                ],
                startPoint: .top,
                endPoint: .bottom
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
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                            .fill(AppTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                                    .stroke(AppTheme.cardBorder, lineWidth: 1)
                            )
                    )
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

// MARK: - Rows / detail

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

struct SessionDetailView: View {
    @EnvironmentObject private var store: SessionStore
    let session: RoomSession
    @State private var showRename = false
    @State private var draftName = ""

    var body: some View {
        List {
            Section {
                NavigationLink {
                    RoomPlannerView(session: session)
                } label: {
                    Label("Room Planner", systemImage: "square.grid.3x3.topleft.filled")
                }
                NavigationLink {
                    FloorPlanView(session: session)
                } label: {
                    Label("Floor plan (from scan)", systemImage: "square.split.bottomrightquarter")
                }
                NavigationLink {
                    RoomViewerView(session: session)
                } label: {
                    Label("View 3D mesh", systemImage: "cube.transparent")
                }
                NavigationLink {
                    ARWalkView(usdzURL: store.usdzURL(for: session))
                } label: {
                    Label("Walk in AR", systemImage: "figure.walk")
                }
            }

            Section("Details") {
                LabeledContent("Walls", value: "\(session.wallCount)")
                LabeledContent("Objects", value: "\(session.objectCount)")
                LabeledContent("Doors", value: "\(session.doorCount)")
                LabeledContent("Windows", value: "\(session.windowCount)")
                if !session.notes.isEmpty {
                    Text(session.notes)
                }
            }

            Section {
                Button("Rename") {
                    draftName = session.name
                    showRename = true
                }
                ShareLink(
                    item: store.usdzURL(for: session),
                    preview: SharePreview(session.name, image: Image(systemName: "cube"))
                ) {
                    Label("Export USDZ", systemImage: "square.and.arrow.up")
                }
                Button("Delete", role: .destructive) {
                    store.delete(session)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.bg)
        .navigationTitle(session.name)
        .tint(AppTheme.blue)
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $draftName)
            Button("Save") {
                store.rename(session, to: draftName)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
