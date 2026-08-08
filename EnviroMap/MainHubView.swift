import SwiftUI

/// Main shell: Tools hub + Library.
struct MainHubView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var tab: Tab = .tools

    enum Tab: Hashable {
        case tools, library
    }

    var body: some View {
        TabView(selection: $tab) {
            ToolsHomeView()
                .tabItem {
                    Label("Tools", systemImage: "square.grid.2x2.fill")
                }
                .tag(Tab.tools)

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "building.2.fill")
                }
                .tag(Tab.library)
        }
        .tint(AppTheme.blue)
    }
}

// MARK: - Tools home

struct ToolsHomeView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var showScanner = false
    @State private var path = NavigationPath()

    private let tools: [ToolItem] = [
        .init(id: .roomPlan, title: "Room Plan", subtitle: "Planner + LiDAR", icon: "square.split.bottomrightquarter.fill", color: AppTheme.blue),
        .init(id: .ruler, title: "Ruler", subtitle: "AR distance", icon: "ruler", color: Color(red: 0.2, green: 0.55, blue: 0.95)),
        .init(id: .level, title: "Level", subtitle: "Surface level", icon: "level", color: Color(red: 0.15, green: 0.6, blue: 0.75)),
        .init(id: .area, title: "Area", subtitle: "Measure sq ft", icon: "triangle", color: Color(red: 0.3, green: 0.45, blue: 0.95)),
        .init(id: .image3d, title: "Image to 3D", subtitle: "Photo plane", icon: "camera.fill", color: Color(red: 0.35, green: 0.4, blue: 0.9)),
        .init(id: .text3d, title: "Text to 3D", subtitle: "Describe a room", icon: "textformat", color: Color(red: 0.25, green: 0.5, blue: 0.95)),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .center) {
                            BrandHeader(height: 68)
                            Spacer(minLength: 8)
                            Text("Free")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppTheme.blue, in: Capsule())
                        }
                        .padding(.top, 10)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Map · Measure · Plan")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.text)

                            Text("LiDAR room capture + precision measuring tools — free while in beta.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            showScanner = true
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.2))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "camera.viewfinder")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Scan environment")
                                        .font(.headline.weight(.bold))
                                    Text("Full LiDAR RoomPlan mesh")
                                        .font(.caption)
                                        .opacity(0.9)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.body.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.blue, AppTheme.blueDeep],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: AppTheme.blue.opacity(0.35), radius: 16, y: 8)
                            )
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 10) {
                            highlightChip(icon: "wave.3.right", title: "LiDAR")
                            highlightChip(icon: "cube", title: "3D Mesh")
                            highlightChip(icon: "figure.walk", title: "Walk AR")
                        }

                        Text("Advanced tools")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.top, 4)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                            ],
                            spacing: 12
                        ) {
                            ForEach(tools) { tool in
                                Button {
                                    handle(tool.id)
                                } label: {
                                    ToolCard(tool: tool)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !store.sessions.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Recent scans")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                ForEach(store.sessions.prefix(3)) { session in
                                    NavigationLink {
                                        SessionDetailView(session: session)
                                    } label: {
                                        SessionRow(session: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ToolRoute.self) { route in
                switch route {
                case .roomPlan:
                    RoomPlanHubView()
                case .planner:
                    RoomPlannerView(session: nil)
                case .ruler:
                    RulerToolView()
                case .level:
                    LevelToolView()
                case .area:
                    AreaToolView()
                case .image3d:
                    ImageTo3DView()
                case .text3d:
                    TextTo3DView()
                case .floorPlan(let id):
                    if let s = store.sessions.first(where: { $0.id == id }) {
                        FloorPlanView(session: s)
                    } else {
                        Text("Scan not found")
                    }
                case .plannerSession(let id):
                    if let s = store.sessions.first(where: { $0.id == id }) {
                        RoomPlannerView(session: s)
                    } else {
                        RoomPlannerView(session: nil)
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScanFlowView()
                    .environmentObject(store)
            }
            .onChange(of: showScanner) { open in
                if !open { store.loadIndex() }
            }
        }
    }

    private var background: some View {
        ZStack {
            AppTheme.bg
            LinearGradient(
                colors: [
                    AppTheme.blue.opacity(0.16),
                    AppTheme.blueSoft.opacity(0.55),
                    AppTheme.bg,
                    Color(red: 0.94, green: 0.96, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(AppTheme.blue.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: 120, y: -180)
        }
    }

    private func highlightChip(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppTheme.blue)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.card.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    private func handle(_ id: ToolID) {
        switch id {
        case .roomPlan:
            path.append(ToolRoute.roomPlan)
        case .ruler:
            path.append(ToolRoute.ruler)
        case .level:
            path.append(ToolRoute.level)
        case .area:
            path.append(ToolRoute.area)
        case .image3d:
            path.append(ToolRoute.image3d)
        case .text3d:
            path.append(ToolRoute.text3d)
        }
    }
}

struct ToolItem: Identifiable {
    let id: ToolID
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
}

enum ToolID: String, Hashable {
    case roomPlan, ruler, level, area, image3d, text3d
}

enum ToolRoute: Hashable {
    case roomPlan
    case planner
    case plannerSession(UUID)
    case ruler, level, area, image3d, text3d
    case floorPlan(UUID)
}

private struct ToolCard: View {
    let tool: ToolItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tool.color.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: tool.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tool.color)
            }
            Text(tool.title)
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text(tool.subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.card.opacity(0.95))
                .shadow(color: AppTheme.blue.opacity(0.06), radius: 12, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
    }
}
