import SwiftUI

/// Main shell: Home + My Rooms (bottom tabs, thumb-friendly).
struct MainHubView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var tab: Tab = .tools

    enum Tab: Hashable {
        case tools, library
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
        }
        .tint(AppTheme.blue)
    }
}

// MARK: - Home (mobile-first: primary action above the fold)

struct ToolsHomeView: View {
    @EnvironmentObject private var store: SessionStore
    var switchToLibrary: () -> Void = {}

    @State private var showScanner = false
    @State private var path = NavigationPath()
    @State private var chipAlert: String?
    @State private var showMoreTools = false

    private var roomCount: Int { store.sessions.count }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                background.ignoresSafeArea()

                // No long ScrollView for core path — fits one phone screen
                VStack(spacing: 0) {
                    // Compact centered brand
                    HStack {
                        Spacer(minLength: 0)
                        BrandHeader(height: 44)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Map your space")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // PRIMARY — thumb zone upper-mid, huge target
                        Button {
                            showScanner = true
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.22))
                                        .frame(width: 52, height: 52)
                                    Image(systemName: "camera.viewfinder")
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Scan a room")
                                        .font(.title3.weight(.bold))
                                    Text("Point the camera · walk slowly")
                                        .font(.caption)
                                        .opacity(0.92)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title2)
                                    .opacity(0.95)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.blue, AppTheme.blueDeep],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: AppTheme.blue.opacity(0.32), radius: 14, y: 6)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scan a room")

                        // Status + My Rooms (one clear secondary)
                        Button {
                            switchToLibrary()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppTheme.blue)
                                    .frame(width: 44, height: 44)
                                    .background(AppTheme.blueSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("My rooms")
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.text)
                                    Text(roomCount == 0 ? "No scans yet" : "\(roomCount) saved")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            .padding(12)
                            .background(cardBg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Quick actions — 3 equal targets, no micro-chips
                        Text("After you scan")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.top, 2)

                        HStack(spacing: 10) {
                            quickAction(
                                title: "3D",
                                icon: "cube.fill",
                                enabled: roomCount > 0
                            ) {
                                openLatestMesh()
                            }
                            quickAction(
                                title: "Walk",
                                icon: "figure.walk",
                                enabled: roomCount > 0
                            ) {
                                openLatestWalkAR()
                            }
                            quickAction(
                                title: "Design",
                                icon: "sofa.fill",
                                enabled: true
                            ) {
                                path.append(ToolRoute.roomPlan)
                            }
                        }

                        Spacer(minLength: 8)

                        // Progressive disclosure — tools behind one control
                        Button {
                            showMoreTools = true
                        } label: {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .foregroundStyle(AppTheme.blue)
                                Text("More tools")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.text)
                                Spacer()
                                Text("Ruler · Level · Area…")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textTertiary)
                                Image(systemName: "chevron.up")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(minHeight: 48)
                            .background(cardBg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ToolRoute.self) { route in
                destination(for: route)
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScanFlowView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showMoreTools) {
                moreToolsSheet
            }
            .onChange(of: showScanner) { _, open in
                if !open { store.loadIndex() }
            }
            .alert("Scan a room first", isPresented: Binding(
                get: { chipAlert != nil },
                set: { if !$0 { chipAlert = nil } }
            )) {
                Button("Scan now") { showScanner = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(chipAlert ?? "")
            }
        }
    }

    // MARK: - More tools (sheet = progressive disclosure)

    private var moreToolsSheet: some View {
        NavigationStack {
            List {
                Section {
                    moreLink("Ruler", "Measure distance", "ruler", .ruler)
                    moreLink("Level", "Check if flat", "level", .level)
                    moreLink("Area", "Square feet", "square.dashed", .area)
                } header: {
                    Text("Measure")
                }

                Section {
                    moreLink("Photo to 3D", "Picture → simple 3D", "camera.fill", .image3d)
                    moreLink("Words to 3D", "Describe a room", "textformat", .text3d)
                } header: {
                    Text("Create")
                }

                Section {
                    Button {
                        showMoreTools = false
                        showScanner = true
                    } label: {
                        Label("Scan a room", systemImage: "camera.viewfinder")
                    }
                    Button {
                        showMoreTools = false
                        switchToLibrary()
                    } label: {
                        Label("My rooms", systemImage: "building.2.fill")
                    }
                } header: {
                    Text("Main")
                }
            }
            .navigationTitle("More tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showMoreTools = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(AppTheme.blue)
    }

    private func moreLink(_ title: String, _ sub: String, _ icon: String, _ route: ToolRoute) -> some View {
        Button {
            showMoreTools = false
            // Delay so sheet dismisses cleanly before push
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                path.append(route)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(AppTheme.text)
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.blue)
            }
        }
    }

    // MARK: - UI bits

    private var cardBg: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.card)
            .shadow(color: AppTheme.blue.opacity(0.05), radius: 8, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
    }

    private func quickAction(title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(enabled ? AppTheme.blue : AppTheme.textTertiary)
                    .frame(width: 44, height: 44)
                    .background(
                        (enabled ? AppTheme.blueSoft : Color.gray.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(enabled ? AppTheme.text : AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(cardBg)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.75)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 88)
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

    // MARK: - Navigation destinations (all features preserved)

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
                needScanPlaceholder(
                    title: "See 3D room",
                    message: "Scan a room first, then open 3D."
                )
            }
        case .walkAR(let id):
            if let s = store.sessions.first(where: { $0.id == id }) {
                ARWalkView(usdzURL: store.usdzURL(for: s))
            } else {
                needScanPlaceholder(
                    title: "Walk in AR",
                    message: "Scan a room first, then walk in AR."
                )
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
            Button("Scan a room") { showScanner = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

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

// MARK: - Pick a saved scan

enum SessionPickPurpose: String, Hashable {
    case mesh
    case walkAR

    var title: String {
        switch self {
        case .mesh: return "Pick a room"
        case .walkAR: return "Pick a room"
        }
    }
}

struct SessionPickerView: View {
    @EnvironmentObject private var store: SessionStore
    let purpose: SessionPickPurpose

    var body: some View {
        List {
            Section {
                ForEach(store.sessions) { session in
                    NavigationLink {
                        destination(for: session)
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

    @ViewBuilder
    private func destination(for session: RoomSession) -> some View {
        switch purpose {
        case .mesh:
            RoomViewerView(session: session)
        case .walkAR:
            ARWalkView(usdzURL: store.usdzURL(for: session))
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
