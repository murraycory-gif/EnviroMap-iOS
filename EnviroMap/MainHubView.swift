import SwiftUI

/// Tabs: Home · My Rooms · More Tools
struct MainHubView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var tab: Tab = .tools

    enum Tab: Hashable {
        case tools, library, more
    }

    var body: some View {
        TabView(selection: $tab) {
            ToolsHomeView(switchToLibrary: { tab = .library })
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.tools)

            LibraryView()
                .tabItem {
                    Label("My Rooms", systemImage: "building.2.fill")
                }
                .tag(Tab.library)

            MoreToolsTabView()
                .tabItem {
                    Label("More Tools", systemImage: "wrench.and.screwdriver.fill")
                }
                .tag(Tab.more)
        }
        .tint(AppTheme.blue)
    }
}

// MARK: - Home

struct ToolsHomeView: View {
    @EnvironmentObject private var store: SessionStore
    var switchToLibrary: () -> Void = {}

    @State private var showScanner = false
    @State private var path = NavigationPath()
    @State private var chipAlert: String?
    @State private var showSettings = false

    private var roomCount: Int { store.sessions.count }

    /// 2-across grid items (measure + post-scan)
    private var gridItems: [HomeGridItem] {
        [
            .init(title: "3D", subtitle: "View scan", icon: "cube.fill", needsScan: true, route: nil, action: .mesh),
            .init(title: "Walk", subtitle: "AR walk", icon: "figure.walk", needsScan: true, route: nil, action: .walk),
            .init(title: "Design", subtitle: "Furniture", icon: "sofa.fill", needsScan: false, route: .roomPlan, action: .route),
            .init(title: "Ruler", subtitle: "Distance", icon: "ruler", needsScan: false, route: .ruler, action: .route),
            .init(title: "Level", subtitle: "Flat check", icon: "level", needsScan: false, route: .level, action: .route),
            .init(title: "Area", subtitle: "Sq ft", icon: "square.dashed", needsScan: false, route: .area, action: .route),
        ]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                background.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Color.clear.frame(width: 40, height: 40)
                        Spacer(minLength: 0)
                        BrandHeader(height: 52)
                        Spacer(minLength: 0)
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.blue)
                                .frame(width: 40, height: 40)
                                .background(AppTheme.blueSoft, in: Circle())
                        }
                        .accessibilityLabel("Settings")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Map your space")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.text)

                            // Primary
                            Button {
                                showScanner = true
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(.white.opacity(0.22))
                                            .frame(width: 56, height: 56)
                                        Image(systemName: "camera.viewfinder")
                                            .font(.title2.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Full 3D Scan")
                                            .font(.title3.weight(.bold))
                                        Text("Capture everything · real colors")
                                            .font(.subheadline)
                                            .opacity(0.92)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill")
                                            .font(.title)
                                }
                                .foregroundStyle(.white)
                                .padding(18)
                                .frame(maxWidth: .infinity, minHeight: 88)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [AppTheme.blue, AppTheme.blueDeep],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: AppTheme.blue.opacity(0.3), radius: 12, y: 5)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // My rooms
                            Button {
                                switchToLibrary()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "building.2.fill")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(AppTheme.blue)
                                        .frame(width: 48, height: 48)
                                        .background(AppTheme.blueSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("My rooms")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(AppTheme.text)
                                        Text(roomCount == 0 ? "No scans yet" : "\(roomCount) saved")
                                            .font(.subheadline)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                                .padding(14)
                                .frame(minHeight: 64)
                                .background(cardBg)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Text("Tools")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.top, 6)

                            // 2-across grid
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10),
                                ],
                                spacing: 10
                            ) {
                                ForEach(gridItems) { item in
                                    gridButton(item)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ToolRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showScanner) {
                FullEnvironmentScanView()
                    .environmentObject(store)
            }
            .onChange(of: showScanner) { _, open in
                if !open { store.loadIndex() }
            }
            .alert("Scan a room first", isPresented: Binding(
                get: { chipAlert != nil },
                set: { if !$0 { chipAlert = nil } }
            )) {
                Button("Start Full Scan") { showScanner = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(chipAlert ?? "")
            }
        }
    }

    private func gridButton(_ item: HomeGridItem) -> some View {
        let enabled = !item.needsScan || roomCount > 0
        return Button {
            switch item.action {
            case .mesh:
                openLatestMesh()
            case .walk:
                openLatestWalkAR()
            case .route:
                if let route = item.route {
                    path.append(route)
                }
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(enabled ? AppTheme.blue : AppTheme.textTertiary)
                    .frame(width: 52, height: 52)
                    .background(
                        (enabled ? AppTheme.blueSoft : Color.gray.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                Text(item.title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(enabled ? AppTheme.text : AppTheme.textTertiary)
                Text(item.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .frame(minHeight: 128)
            .background(cardBg)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.72)
        }
        .buttonStyle(.plain)
    }

    private var cardBg: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.card)
            .shadow(color: AppTheme.blue.opacity(0.05), radius: 8, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
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
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func destination(for route: ToolRoute) -> some View {
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
        case .mesh(let id):
            if let s = store.sessions.first(where: { $0.id == id }) {
                RoomViewerView(session: s)
            } else {
                needScanPlaceholder(title: "See 3D room", message: "Scan a room first, then open 3D.")
            }
        case .walkAR(let id):
            if let s = store.sessions.first(where: { $0.id == id }) {
                ARWalkView(usdzURL: store.usdzURL(for: s))
            } else {
                needScanPlaceholder(title: "Walk in AR", message: "Scan a room first, then walk in AR.")
            }
        case .pickSession(let purpose):
            SessionPickerView(purpose: purpose)
        }
    }

    private func needScanPlaceholder(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.blue)
            Text(title).font(.title2.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Full 3D Scan") { showScanner = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openLatestMesh() {
        store.loadIndex()
        if store.sessions.isEmpty {
            chipAlert = "Scan a room first. Then you can see it in 3D."
            return
        }
        if store.sessions.count == 1, let s = store.sessions.first {
            path.append(ToolRoute.mesh(s.id))
        } else {
            path.append(ToolRoute.pickSession(.mesh))
        }
    }

    private func openLatestWalkAR() {
        store.loadIndex()
        if store.sessions.isEmpty {
            chipAlert = "Scan a room first. Then you can walk in AR."
            return
        }
        if store.sessions.count == 1, let s = store.sessions.first {
            path.append(ToolRoute.walkAR(s.id))
        } else {
            path.append(ToolRoute.pickSession(.walkAR))
        }
    }
}

// MARK: - More Tools tab (was pull-up sheet)

struct MoreToolsTabView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var path = NavigationPath()
    @State private var showScanner = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AppTheme.bg.ignoresSafeArea()
                LinearGradient(
                    colors: [AppTheme.blue.opacity(0.10), AppTheme.bg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("More tools")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.text)
                            .padding(.top, 8)

                        Text("Extra ways to create and explore")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                            ],
                            spacing: 10
                        ) {
                            moreCard("Photo to 3D", "Picture → 3D", "camera.fill") {
                                path.append(ToolRoute.image3d)
                            }
                            moreCard("Words to 3D", "Describe a room", "textformat") {
                                path.append(ToolRoute.text3d)
                            }
                            moreCard("Room design", "Planner + plan", "sofa.fill") {
                                path.append(ToolRoute.roomPlan)
                            }
                            moreCard("Scan room", "LiDAR capture", "camera.viewfinder") {
                                showScanner = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ToolRoute.self) { route in
                switch route {
                case .image3d: ImageTo3DView()
                case .text3d: TextTo3DView()
                case .roomPlan: RoomPlanHubView()
                case .planner: RoomPlannerView(session: nil)
                case .ruler: RulerToolView()
                case .level: LevelToolView()
                case .area: AreaToolView()
                default:
                    Text("Open from Home")
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                FullEnvironmentScanView()
                    .environmentObject(store)
            }
        }
    }

    private func moreCard(_ title: String, _ sub: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.blueSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .multilineTextAlignment(.center)
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .frame(minHeight: 120)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grid model

struct HomeGridItem: Identifiable {
    enum Action { case mesh, walk, route }
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let needsScan: Bool
    let route: ToolRoute?
    let action: Action
}

// MARK: - Session picker

enum SessionPickPurpose: String, Hashable {
    case mesh
    case walkAR

    var title: String { "Pick a room" }
}

struct SessionPickerView: View {
    @EnvironmentObject private var store: SessionStore
    let purpose: SessionPickPurpose

    var body: some View {
        List {
            Section {
                ForEach(store.sessions) { session in
                    NavigationLink {
                        switch purpose {
                        case .mesh:
                            RoomViewerView(session: session)
                        case .walkAR:
                            ARWalkView(usdzURL: store.usdzURL(for: session))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.name).font(.headline)
                            Text("\(session.wallCount) walls · \(session.objectCount) objects")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Tap a room")
            }
        }
        .navigationTitle(purpose.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No rooms yet",
                    systemImage: "camera.viewfinder",
                    description: Text("Scan a room first.")
                )
            }
        }
    }
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
    case mesh(UUID)
    case walkAR(UUID)
    case pickSession(SessionPickPurpose)
}
