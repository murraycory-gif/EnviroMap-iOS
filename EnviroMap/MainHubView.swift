import SwiftUI

/// Main shell: simple Home + My Rooms.
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

// MARK: - Super-simple home

struct ToolsHomeView: View {
    @EnvironmentObject private var store: SessionStore
    var switchToLibrary: () -> Void = {}

    @State private var showScanner = false
    @State private var path = NavigationPath()
    @State private var chipAlert: String?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Brand
                        HStack {
                            BrandHeader(height: 56)
                            Spacer()
                        }
                        .padding(.top, 8)

                        // Plain headline
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What do you want to do?")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.text)
                            Text("Start at step 1. Everything else is optional.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        // STEP 1 — Scan
                        stepLabel(1, "Scan a room")
                        Button {
                            showScanner = true
                        } label: {
                            bigPrimary(
                                title: "Scan a room",
                                subtitle: "Use the camera to map your space",
                                icon: "camera.viewfinder"
                            )
                        }
                        .buttonStyle(.plain)

                        // STEP 2 — After scanning
                        stepLabel(2, "Then open your room")
                        VStack(spacing: 10) {
                            simpleRow(
                                title: "My saved rooms",
                                subtitle: store.sessions.isEmpty
                                    ? "None yet — scan first"
                                    : "\(store.sessions.count) saved on this phone",
                                icon: "building.2.fill",
                                color: AppTheme.blue
                            ) {
                                switchToLibrary()
                            }

                            simpleRow(
                                title: "See 3D room",
                                subtitle: "Look at your scan from all sides",
                                icon: "cube.fill",
                                color: Color(red: 0.25, green: 0.5, blue: 0.95)
                            ) {
                                openLatestMesh()
                            }

                            simpleRow(
                                title: "Walk in AR",
                                subtitle: "Stand in the real room and walk the model",
                                icon: "figure.walk",
                                color: Color(red: 0.2, green: 0.55, blue: 0.85)
                            ) {
                                openLatestWalkAR()
                            }

                            simpleRow(
                                title: "Design the room",
                                subtitle: "Add furniture · floor plan · planner",
                                icon: "sofa.fill",
                                color: Color(red: 0.3, green: 0.45, blue: 0.95)
                            ) {
                                path.append(ToolRoute.roomPlan)
                            }
                        }

                        // STEP 3 — Measure
                        stepLabel(3, "Measure (optional)")
                        VStack(spacing: 10) {
                            simpleRow(
                                title: "Ruler",
                                subtitle: "Measure how far something is",
                                icon: "ruler",
                                color: Color(red: 0.2, green: 0.55, blue: 0.95)
                            ) {
                                path.append(ToolRoute.ruler)
                            }
                            simpleRow(
                                title: "Level",
                                subtitle: "Check if a surface is flat",
                                icon: "level",
                                color: Color(red: 0.15, green: 0.6, blue: 0.75)
                            ) {
                                path.append(ToolRoute.level)
                            }
                            simpleRow(
                                title: "Area",
                                subtitle: "Find square feet of a space",
                                icon: "square.dashed",
                                color: Color(red: 0.3, green: 0.45, blue: 0.95)
                            ) {
                                path.append(ToolRoute.area)
                            }
                        }

                        // More
                        stepLabel(nil, "More tools")
                        VStack(spacing: 10) {
                            simpleRow(
                                title: "Photo to 3D",
                                subtitle: "Turn a picture into a simple 3D shape",
                                icon: "camera.fill",
                                color: Color(red: 0.35, green: 0.4, blue: 0.9)
                            ) {
                                path.append(ToolRoute.image3d)
                            }
                            simpleRow(
                                title: "Words to 3D",
                                subtitle: "Type a room idea and preview it",
                                icon: "textformat",
                                color: Color(red: 0.25, green: 0.5, blue: 0.95)
                            ) {
                                path.append(ToolRoute.text3d)
                            }
                        }

                        // Recent (if any)
                        if !store.sessions.isEmpty {
                            stepLabel(nil, "Recent rooms")
                            ForEach(store.sessions.prefix(3)) { session in
                                NavigationLink {
                                    SessionDetailView(session: session)
                                } label: {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Tip: Scan first. Then open My Rooms to view, design, or walk.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
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
                case .mesh(let id):
                    if let s = store.sessions.first(where: { $0.id == id }) {
                        RoomViewerView(session: s)
                    } else {
                        needScanPlaceholder(
                            title: "See 3D room",
                            message: "Scan a room first. Then come back here to look at it in 3D."
                        )
                    }
                case .walkAR(let id):
                    if let s = store.sessions.first(where: { $0.id == id }) {
                        ARWalkView(usdzURL: store.usdzURL(for: s))
                    } else {
                        needScanPlaceholder(
                            title: "Walk in AR",
                            message: "Scan a room first. Then you can walk through it with the camera."
                        )
                    }
                case .pickSession(let purpose):
                    SessionPickerView(purpose: purpose)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScanFlowView()
                    .environmentObject(store)
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

    // MARK: UI pieces

    private func stepLabel(_ number: Int?, _ text: String) -> some View {
        HStack(spacing: 10) {
            if let number {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.blue, in: Circle())
            }
            Text(text)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
        }
        .padding(.top, 6)
    }

    private func bigPrimary(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.92)
            }
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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

    private func simpleRow(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.card)
                    .shadow(color: AppTheme.blue.opacity(0.05), radius: 10, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func needScanPlaceholder(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.blue)
            Text(title)
                .font(.title2.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Scan a room") {
                showScanner = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var background: some View {
        ZStack {
            AppTheme.bg
            LinearGradient(
                colors: [
                    AppTheme.blue.opacity(0.14),
                    AppTheme.blueSoft.opacity(0.5),
                    AppTheme.bg,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(AppTheme.blue.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: 110, y: -160)
        }
    }

    // MARK: Actions (same as before — all still work)

    private func openLatestMesh() {
        store.loadIndex()
        if store.sessions.isEmpty {
            chipAlert = "First scan a room. Then you can see it in 3D."
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
            chipAlert = "First scan a room. Then you can walk in AR."
            return
        }
        if store.sessions.count == 1, let s = store.sessions.first {
            path.append(ToolRoute.walkAR(s.id))
        } else {
            path.append(ToolRoute.pickSession(.walkAR))
        }
    }
}

// MARK: - Pick a saved scan for Mesh / Walk AR

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
                            Text(session.name)
                                .font(.headline)
                            Text("\(session.wallCount) walls · \(session.objectCount) objects")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Tap a room")
            } footer: {
                Text("These are rooms you scanned on this phone.")
            }
        }
        .navigationTitle(purpose.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No rooms yet",
                    systemImage: "camera.viewfinder",
                    description: Text("Go back and tap Scan a room.")
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
