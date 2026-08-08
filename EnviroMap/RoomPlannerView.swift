import SwiftUI
import SceneKit
import RoomPlan
import simd

// MARK: - Models

enum FurnitureKind: String, CaseIterable, Identifiable, Codable {
    case sofa, armchair, coffeeTable, diningTable, chair, bed, nightstand
    case desk, bookshelf, tvStand, plant, lamp, rug, fridge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sofa: return "Sofa"
        case .armchair: return "Lounge chair"
        case .coffeeTable: return "Coffee table"
        case .diningTable: return "Dining table"
        case .chair: return "Side chair"
        case .bed: return "Bed"
        case .nightstand: return "Nightstand"
        case .desk: return "Desk"
        case .bookshelf: return "Bookshelf"
        case .tvStand: return "Media console"
        case .plant: return "Plant"
        case .lamp: return "Floor lamp"
        case .rug: return "Area rug"
        case .fridge: return "Fridge"
        }
    }

    var category: String {
        switch self {
        case .sofa, .armchair, .coffeeTable, .rug: return "Living"
        case .bed, .nightstand: return "Bedroom"
        case .diningTable, .chair, .fridge: return "Kitchen"
        case .desk, .bookshelf, .tvStand, .lamp, .plant: return "Study"
        }
    }

    var symbol: String {
        switch self {
        case .sofa: return "sofa.fill"
        case .armchair: return "chair.fill"
        case .coffeeTable, .diningTable: return "table.furniture.fill"
        case .chair: return "chair.lounge.fill"
        case .bed: return "bed.double.fill"
        case .nightstand: return "cabinet.fill"
        case .desk: return "desktopcomputer"
        case .bookshelf: return "books.vertical.fill"
        case .tvStand: return "tv.fill"
        case .plant: return "leaf.fill"
        case .lamp: return "lamp.floor.fill"
        case .rug: return "rectangle.fill"
        case .fridge: return "refrigerator.fill"
        }
    }

    /// Width × depth in feet
    var sizeFt: CGSize {
        switch self {
        case .sofa: return CGSize(width: 7.0, height: 3.0)
        case .armchair: return CGSize(width: 3.0, height: 3.0)
        case .coffeeTable: return CGSize(width: 4.0, height: 2.0)
        case .diningTable: return CGSize(width: 6.0, height: 3.5)
        case .chair: return CGSize(width: 1.8, height: 1.8)
        case .bed: return CGSize(width: 5.3, height: 6.7)
        case .nightstand: return CGSize(width: 1.8, height: 1.5)
        case .desk: return CGSize(width: 5.0, height: 2.5)
        case .bookshelf: return CGSize(width: 3.0, height: 1.2)
        case .tvStand: return CGSize(width: 5.5, height: 1.5)
        case .plant: return CGSize(width: 1.5, height: 1.5)
        case .lamp: return CGSize(width: 1.2, height: 1.2)
        case .rug: return CGSize(width: 8.0, height: 5.0)
        case .fridge: return CGSize(width: 3.0, height: 2.5)
        }
    }

    /// Height in feet (for 3D)
    var heightFt: Double {
        switch self {
        case .sofa: return 2.8
        case .armchair: return 3.0
        case .coffeeTable: return 1.5
        case .diningTable: return 2.5
        case .chair: return 3.2
        case .bed: return 2.0
        case .nightstand: return 2.2
        case .desk: return 2.5
        case .bookshelf: return 6.5
        case .tvStand: return 1.8
        case .plant: return 3.5
        case .lamp: return 5.5
        case .rug: return 0.08
        case .fridge: return 5.8
        }
    }

    var tint: Color {
        switch self {
        case .sofa: return Color(red: 0.22, green: 0.42, blue: 0.92)
        case .armchair: return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .coffeeTable, .diningTable, .desk, .tvStand, .nightstand:
            return Color(red: 0.62, green: 0.45, blue: 0.30)
        case .chair: return Color(red: 0.45, green: 0.52, blue: 0.62)
        case .bed: return Color(red: 0.55, green: 0.62, blue: 0.88)
        case .bookshelf: return Color(red: 0.48, green: 0.34, blue: 0.24)
        case .plant: return Color(red: 0.22, green: 0.68, blue: 0.42)
        case .lamp: return Color(red: 0.95, green: 0.78, blue: 0.28)
        case .rug: return Color(red: 0.55, green: 0.68, blue: 0.95)
        case .fridge: return Color(red: 0.78, green: 0.82, blue: 0.88)
        }
    }

    var scnColor: UIColor {
        UIColor(tint)
    }
}

struct PlacedFurniture: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: FurnitureKind
    var xFt: Double
    var yFt: Double
    var rotationDeg: Double

    static func make(_ kind: FurnitureKind, at x: Double, y: Double) -> PlacedFurniture {
        PlacedFurniture(id: UUID(), kind: kind, xFt: x, yFt: y, rotationDeg: 0)
    }
}

struct RoomLayout: Codable, Equatable {
    var roomWidthFt: Double
    var roomDepthFt: Double
    var items: [PlacedFurniture]
    var wallSegments: [WallSeg]

    struct WallSeg: Codable, Equatable {
        var x1: Double, y1: Double, x2: Double, y2: Double
    }

    static func empty(width: Double = 14, depth: Double = 16) -> RoomLayout {
        RoomLayout(roomWidthFt: width, roomDepthFt: depth, items: [], wallSegments: [])
    }
}

enum PlannerMode: String, CaseIterable {
    case plan = "Plan"
    case threeD = "3D"
}

// MARK: - Main planner

struct RoomPlannerView: View {
    @EnvironmentObject private var store: SessionStore
    var session: RoomSession? = nil

    @State private var layout = RoomLayout.empty()
    @State private var selectedId: UUID?
    @State private var mode: PlannerMode = .plan
    @State private var catalogCategory = "All"
    @State private var showResize = false
    @State private var widthText = "14"
    @State private var depthText = "16"
    @State private var showScanner = false
    @State private var toast: String?

    private let categories = ["All", "Living", "Bedroom", "Kitchen", "Study"]

    private var storageKey: String {
        if let session { return "enviromap.layout.\(session.id.uuidString)" }
        return "enviromap.layout.blank"
    }

    private var filteredCatalog: [FurnitureKind] {
        if catalogCategory == "All" { return FurnitureKind.allCases }
        return FurnitureKind.allCases.filter { $0.category == catalogCategory }
    }

    var body: some View {
        ZStack {
            // Soft studio background
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.95, blue: 1.0),
                    AppTheme.bg,
                    Color(red: 0.90, green: 0.93, blue: 0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating header chips
                topChrome
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                // Stage
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: AppTheme.blue.opacity(0.10), radius: 24, y: 10)
                        .padding(.horizontal, 12)

                    if mode == .plan {
                        planCanvas
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else {
                        RoomPlanner3DView(layout: layout, selectedId: selectedId)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
                .frame(maxHeight: .infinity)

                if let selected = selectedItem, mode == .plan {
                    selectionBar(selected)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                modernCatalog
            }
        }
        .navigationTitle(session?.name ?? "Room Planner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        mode = mode == .plan ? .threeD : .plan
                    } label: {
                        Label(mode == .plan ? "View in 3D" : "Edit on plan", systemImage: mode == .plan ? "cube.transparent" : "square.grid.3x3")
                    }
                    Button {
                        widthText = String(format: "%.0f", layout.roomWidthFt)
                        depthText = String(format: "%.0f", layout.roomDepthFt)
                        showResize = true
                    } label: {
                        Label("Room size", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    if session == nil {
                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan real room", systemImage: "camera.viewfinder")
                        }
                    }
                    Button(role: .destructive) {
                        layout.items = []
                        selectedId = nil
                        flash("Cleared")
                    } label: {
                        Label("Clear furniture", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.blue)
                        .font(.title3)
                }
            }
        }
        .onAppear {
            loadLayout()
            if let session { importWallsIfNeeded(from: session) }
        }
        .onChange(of: layout) { _, _ in saveLayout() }
        .alert("Room size (feet)", isPresented: $showResize) {
            TextField("Width", text: $widthText).keyboardType(.decimalPad)
            TextField("Depth", text: $depthText).keyboardType(.decimalPad)
            Button("Apply") { applyResize() }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScanFlowView().environmentObject(store)
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppTheme.blueDeep.opacity(0.95)))
                    .padding(.top, 4)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedId)
        .animation(.easeInOut(duration: 0.25), value: mode)
    }

    // MARK: Chrome

    private var topChrome: some View {
        HStack(spacing: 10) {
            // Mode pill
            HStack(spacing: 0) {
                ForEach(PlannerMode.allCases, id: \.self) { m in
                    Button {
                        mode = m
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: m == .plan ? "square.grid.3x3.fill" : "cube.fill")
                                .font(.caption2.weight(.bold))
                            Text(m.rawValue)
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(mode == m ? .white : AppTheme.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if mode == m {
                                Capsule().fill(
                                    LinearGradient(colors: [AppTheme.blue, AppTheme.blueDeep], startPoint: .leading, endPoint: .trailing)
                                )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(AppTheme.blueSoft))

            Spacer()

            Label(
                String(format: "%.0f×%.0f ft", layout.roomWidthFt, layout.roomDepthFt),
                systemImage: "ruler"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white).shadow(color: .black.opacity(0.04), radius: 6, y: 2))

            Text("\(layout.items.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(minWidth: 28, minHeight: 28)
                .background(Circle().fill(AppTheme.blue))
        }
    }

    // MARK: Plan canvas

    private var planCanvas: some View {
        GeometryReader { geo in
            let m = CanvasMetrics(size: geo.size, roomW: layout.roomWidthFt, roomD: layout.roomDepthFt)
            ZStack {
                // Floor wash
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.98, blue: 1.0),
                        Color(red: 0.92, green: 0.94, blue: 0.98),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                gridLayer(m)
                wallsLayer(m)
                roomOutline(m)

                // Soft floor shadow plate
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.blue.opacity(0.04))
                    .frame(width: m.roomWPx, height: m.roomDPx)
                    .position(x: m.origin.x + m.roomWPx / 2, y: m.origin.y + m.roomDPx / 2)

                ForEach(layout.items) { item in
                    furnitureTile(item, metrics: m)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selectedId = nil }
            }
        }
    }

    private func gridLayer(_ m: CanvasMetrics) -> some View {
        Path { p in
            let step = m.scale
            var x = m.origin.x
            while x <= m.origin.x + m.roomWPx + 0.5 {
                p.move(to: CGPoint(x: x, y: m.origin.y))
                p.addLine(to: CGPoint(x: x, y: m.origin.y + m.roomDPx))
                x += step
            }
            var y = m.origin.y
            while y <= m.origin.y + m.roomDPx + 0.5 {
                p.move(to: CGPoint(x: m.origin.x, y: y))
                p.addLine(to: CGPoint(x: m.origin.x + m.roomWPx, y: y))
                y += step
            }
        }
        .stroke(AppTheme.blue.opacity(0.08), lineWidth: 1)
    }

    private func roomOutline(_ m: CanvasMetrics) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(
                LinearGradient(colors: [AppTheme.blue, AppTheme.blueDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 3
            )
            .frame(width: m.roomWPx, height: m.roomDPx)
            .position(x: m.origin.x + m.roomWPx / 2, y: m.origin.y + m.roomDPx / 2)
    }

    private func wallsLayer(_ m: CanvasMetrics) -> some View {
        Path { p in
            for w in layout.wallSegments {
                p.move(to: m.point(xFt: w.x1, yFt: w.y1))
                p.addLine(to: m.point(xFt: w.x2, yFt: w.y2))
            }
        }
        .stroke(AppTheme.blueDeep.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    private func furnitureTile(_ item: PlacedFurniture, metrics m: CanvasMetrics) -> some View {
        let size = item.kind.sizeFt
        let w = max(28, size.width * m.scale)
        let h = max(28, size.height * m.scale)
        let center = m.point(xFt: item.xFt, yFt: item.yFt)
        let selected = item.id == selectedId

        return ZStack {
            // Isometric-ish base
            RoundedRectangle(cornerRadius: item.kind == .rug ? 10 : 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            item.kind.tint.opacity(item.kind == .rug ? 0.35 : 0.95),
                            item.kind.tint.opacity(item.kind == .rug ? 0.2 : 0.7),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: item.kind == .rug ? 10 : 12, style: .continuous)
                        .stroke(selected ? Color.white : Color.white.opacity(0.35), lineWidth: selected ? 3 : 1)
                )
                .shadow(color: item.kind.tint.opacity(selected ? 0.45 : 0.25), radius: selected ? 12 : 6, y: 4)

            // 3D-ish top highlight
            if item.kind != .rug {
                VStack(spacing: 4) {
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: min(22, min(w, h) * 0.28), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .symbolRenderingMode(.hierarchical)
                    if min(w, h) > 40 {
                        Text(item.kind.title)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(item.rotationDeg))
        .position(center)
        .scaleEffect(selected ? 1.04 : 1)
        .gesture(
            DragGesture()
                .onChanged { value in
                    selectedId = item.id
                    if let idx = layout.items.firstIndex(where: { $0.id == item.id }) {
                        let ft = m.feet(from: value.location)
                        layout.items[idx].xFt = min(max(ft.x, 0.6), layout.roomWidthFt - 0.6)
                        layout.items[idx].yFt = min(max(ft.y, 0.6), layout.roomDepthFt - 0.6)
                    }
                }
        )
        .onTapGesture { selectedId = item.id }
        .zIndex(item.kind == .rug ? 0 : (selected ? 20 : 2))
    }

    // MARK: Selection bar

    private var selectedItem: PlacedFurniture? {
        guard let selectedId else { return nil }
        return layout.items.first { $0.id == selectedId }
    }

    private func selectionBar(_ item: PlacedFurniture) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(item.kind.tint.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(item.kind.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Text(String(format: "%.0f×%.0f×%.0f ft", item.kind.sizeFt.width, item.kind.sizeFt.height, item.kind.heightFt))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            controlBtn("rotate.left") { rotateSelected(-15) }
            controlBtn("rotate.right") { rotateSelected(15) }
            controlBtn("trash", color: .red) { deleteSelected() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func controlBtn(_ icon: String, color: Color = AppTheme.blue, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.9)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Catalog

    private var modernCatalog: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            catalogCategory = cat
                        } label: {
                            Text(cat)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(catalogCategory == cat ? .white : AppTheme.blue)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule().fill(catalogCategory == cat ? AppTheme.blue : AppTheme.blueSoft)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            HStack {
                Text("3D catalog")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Text(mode == .plan ? "Tap to place · drag to move" : "Switch to Plan to edit")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filteredCatalog) { kind in
                        Button {
                            place(kind)
                        } label: {
                            catalogCard(kind)
                        }
                        .buttonStyle(.plain)
                        .disabled(mode == .threeD)
                        .opacity(mode == .threeD ? 0.55 : 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 20, y: -6)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func catalogCard(_ kind: FurnitureKind) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [kind.tint.opacity(0.25), kind.tint.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 64)

                // Mini “3D” block stack
                FurnitureGlyph(kind: kind)
                    .frame(width: 48, height: 44)
            }

            Text(kind.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)
            Text(String(format: "%.0f×%.0f′", kind.sizeFt.width, kind.sizeFt.height))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(width: 88)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    // MARK: Actions

    private func place(_ kind: FurnitureKind) {
        if mode == .threeD { mode = .plan }
        let jitter = Double(layout.items.count % 5) * 0.45
        var item = PlacedFurniture.make(kind, at: layout.roomWidthFt / 2 + jitter, y: layout.roomDepthFt / 2 + jitter)
        item.xFt = min(max(item.xFt, 1), layout.roomWidthFt - 1)
        item.yFt = min(max(item.yFt, 1), layout.roomDepthFt - 1)
        layout.items.append(item)
        selectedId = item.id
        flash("Placed \(kind.title)")
    }

    private func rotateSelected(_ deg: Double) {
        guard let selectedId, let idx = layout.items.firstIndex(where: { $0.id == selectedId }) else { return }
        layout.items[idx].rotationDeg += deg
    }

    private func deleteSelected() {
        guard let selectedId else { return }
        layout.items.removeAll { $0.id == selectedId }
        self.selectedId = nil
    }

    private func applyResize() {
        layout.roomWidthFt = min(max(Double(widthText) ?? 14, 6), 60)
        layout.roomDepthFt = min(max(Double(depthText) ?? 16, 6), 60)
        flash("Room \(Int(layout.roomWidthFt))×\(Int(layout.roomDepthFt)) ft")
    }

    private func flash(_ msg: String) {
        withAnimation { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation { toast = nil }
        }
    }

    private func saveLayout() {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadLayout() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(RoomLayout.self, from: data) {
            layout = decoded
        } else {
            layout = .empty()
        }
    }

    private func importWallsIfNeeded(from session: RoomSession) {
        guard layout.wallSegments.isEmpty else { return }
        let url = store.folderURL(for: session).appendingPathComponent("captured_room.json")
        guard let data = try? Data(contentsOf: url),
              let room = try? JSONDecoder().decode(CapturedRoom.self, from: data)
        else { return }

        var segs: [RoomLayout.WallSeg] = []
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude

        for w in room.walls {
            let ends = wallEndpoints(transform: w.transform, length: w.dimensions.x)
            let x1 = Double(ends.0.x), z1 = Double(ends.0.z)
            let x2 = Double(ends.1.x), z2 = Double(ends.1.z)
            segs.append(.init(x1: x1, y1: z1, x2: x2, y2: z2))
            minX = min(minX, x1, x2); maxX = max(maxX, x1, x2)
            minZ = min(minZ, z1, z2); maxZ = max(maxZ, z1, z2)
        }
        guard !segs.isEmpty, minX.isFinite else { return }

        let m2ft = 3.28084
        let pad = 1.0
        layout.wallSegments = segs.map {
            .init(
                x1: ($0.x1 - minX) * m2ft + pad,
                y1: ($0.y1 - minZ) * m2ft + pad,
                x2: ($0.x2 - minX) * m2ft + pad,
                y2: ($0.y2 - minZ) * m2ft + pad
            )
        }
        layout.roomWidthFt = max(8, (maxX - minX) * m2ft + pad * 2)
        layout.roomDepthFt = max(8, (maxZ - minZ) * m2ft + pad * 2)
        saveLayout()
        flash("LiDAR walls loaded")
    }

    private func wallEndpoints(transform: simd_float4x4, length: Float) -> (SIMD3<Float>, SIMD3<Float>) {
        let half = length / 2
        let w0 = simd_mul(transform, SIMD4<Float>(-half, 0, 0, 1))
        let w1 = simd_mul(transform, SIMD4<Float>(half, 0, 0, 1))
        return (SIMD3(w0.x, w0.y, w0.z), SIMD3(w1.x, w1.y, w1.z))
    }
}

// MARK: - Mini 3D glyph (catalog)

private struct FurnitureGlyph: View {
    let kind: FurnitureKind

    var body: some View {
        ZStack {
            // shadow plate
            Ellipse()
                .fill(Color.black.opacity(0.12))
                .frame(width: 34, height: 10)
                .offset(y: 16)

            // extruded body
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [kind.tint, kind.tint.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: kind == .rug ? 40 : 30, height: kind == .lamp ? 36 : (kind == .bookshelf ? 34 : 22))
                .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0))
                .rotation3DEffect(.degrees(-22), axis: (x: 0, y: 1, z: 0))
                .shadow(color: kind.tint.opacity(0.4), radius: 4, y: 3)

            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .offset(y: kind == .rug ? 0 : -2)
        }
    }
}

// MARK: - SceneKit 3D room

struct RoomPlanner3DView: UIViewRepresentable {
    let layout: RoomLayout
    let selectedId: UUID?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.backgroundColor = UIColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        context.coordinator.view = view
        context.coordinator.build(layout: layout, selectedId: selectedId)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.build(layout: layout, selectedId: selectedId)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var view: SCNView?
        private var lastSignature: String = ""

        func build(layout: RoomLayout, selectedId: UUID?) {
            let sig = "\(layout.roomWidthFt)x\(layout.roomDepthFt)-\(layout.items.map { "\($0.id.uuidString.prefix(4))\($0.xFt)\($0.yFt)\($0.rotationDeg)\($0.kind.rawValue)" }.joined())-\(selectedId?.uuidString ?? "")"
            guard sig != lastSignature, let scnView = view else { return }
            lastSignature = sig

            let scene = SCNScene()

            // Lights
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 400
            ambient.light?.color = UIColor.white
            scene.rootNode.addChildNode(ambient)

            let sun = SCNNode()
            sun.light = SCNLight()
            sun.light?.type = .directional
            sun.light?.intensity = 900
            sun.light?.castsShadow = true
            sun.light?.shadowMode = .deferred
            sun.light?.shadowColor = UIColor.black.withAlphaComponent(0.35)
            sun.eulerAngles = SCNVector3(-0.9, 0.6, 0)
            scene.rootNode.addChildNode(sun)

            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .omni
            fill.light?.intensity = 350
            fill.position = SCNVector3(0, 12, 0)
            scene.rootNode.addChildNode(fill)

            // Units: 1 SceneKit unit = 1 foot
            let W = Float(layout.roomWidthFt)
            let D = Float(layout.roomDepthFt)

            // Floor
            let floor = SCNBox(width: CGFloat(W), height: 0.08, length: CGFloat(D), chamferRadius: 0.02)
            floor.firstMaterial = mat(UIColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1), roughness: 0.85)
            let floorNode = SCNNode(geometry: floor)
            floorNode.position = SCNVector3(W / 2, 0, D / 2)
            scene.rootNode.addChildNode(floorNode)

            // Grid on floor
            let grid = makeGrid(width: W, depth: D)
            grid.position = SCNVector3(W / 2, 0.05, D / 2)
            scene.rootNode.addChildNode(grid)

            // Walls (low)
            addWalls(to: scene.rootNode, W: W, D: D)

            // LiDAR wall segments if any
            for seg in layout.wallSegments {
                let dx = Float(seg.x2 - seg.x1)
                let dz = Float(seg.y2 - seg.y1)
                let len = sqrt(dx * dx + dz * dz)
                guard len > 0.05 else { continue }
                let wall = SCNBox(width: CGFloat(len), height: 3.0, length: 0.18, chamferRadius: 0.02)
                wall.firstMaterial = mat(UIColor(red: 0.55, green: 0.68, blue: 0.95, alpha: 0.55), roughness: 0.6)
                let node = SCNNode(geometry: wall)
                node.position = SCNVector3(Float(seg.x1 + seg.x2) / 2, 1.5, Float(seg.y1 + seg.y2) / 2)
                node.eulerAngles.y = atan2(dx, dz) + .pi / 2
                scene.rootNode.addChildNode(node)
            }

            // Furniture
            for item in layout.items {
                let node = makeFurnitureNode(item, selected: item.id == selectedId)
                // plan y → 3D z
                node.position = SCNVector3(Float(item.xFt), 0, Float(item.yFt))
                node.eulerAngles.y = Float(-item.rotationDeg * .pi / 180)
                scene.rootNode.addChildNode(node)
            }

            // Camera
            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 50
            cam.camera?.wantsHDR = true
            let cx = W / 2
            let cz = D / 2
            cam.position = SCNVector3(cx + W * 0.55, max(W, D) * 0.75, cz + D * 0.7)
            cam.look(at: SCNVector3(cx, 0.5, cz))
            scene.rootNode.addChildNode(cam)

            scnView.pointOfView = cam
            scnView.scene = scene
        }

        private func addWalls(to root: SCNNode, W: Float, D: Float) {
            let h: Float = 0.4
            let t: Float = 0.12
            let c = UIColor(red: 0.75, green: 0.82, blue: 0.95, alpha: 1)
            // back
            let back = SCNBox(width: CGFloat(W), height: CGFloat(h), length: CGFloat(t), chamferRadius: 0.02)
            back.firstMaterial = mat(c, roughness: 0.7)
            let bn = SCNNode(geometry: back)
            bn.position = SCNVector3(W / 2, h / 2, 0)
            root.addChildNode(bn)
            // left
            let left = SCNBox(width: CGFloat(t), height: CGFloat(h), length: CGFloat(D), chamferRadius: 0.02)
            left.firstMaterial = mat(c, roughness: 0.7)
            let ln = SCNNode(geometry: left)
            ln.position = SCNVector3(0, h / 2, D / 2)
            root.addChildNode(ln)
        }

        private func makeGrid(width W: Float, depth D: Float) -> SCNNode {
            let path = UIBezierPath()
            let step: Float = 1
            var x: Float = -W / 2
            while x <= W / 2 {
                path.move(to: CGPoint(x: CGFloat(x), y: CGFloat(-D / 2)))
                path.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(D / 2)))
                x += step
            }
            var z: Float = -D / 2
            while z <= D / 2 {
                path.move(to: CGPoint(x: CGFloat(-W / 2), y: CGFloat(z)))
                path.addLine(to: CGPoint(x: CGFloat(W / 2), y: CGFloat(z)))
                z += step
            }
            let shape = SCNShape(path: path, extrusionDepth: 0.01)
            shape.firstMaterial = mat(UIColor(red: 0.55, green: 0.65, blue: 0.9, alpha: 0.25), roughness: 1)
            let node = SCNNode(geometry: shape)
            node.eulerAngles.x = .pi / 2
            return node
        }

        private func makeFurnitureNode(_ item: PlacedFurniture, selected: Bool) -> SCNNode {
            let kind = item.kind
            let w = CGFloat(kind.sizeFt.width)
            let d = CGFloat(kind.sizeFt.height)
            let h = CGFloat(kind.heightFt)
            let parent = SCNNode()

            switch kind {
            case .rug:
                let rug = SCNBox(width: w, height: 0.06, length: d, chamferRadius: 0.04)
                rug.firstMaterial = mat(kind.scnColor.withAlphaComponent(0.85), roughness: 0.9)
                let n = SCNNode(geometry: rug)
                n.position.y = 0.05
                parent.addChildNode(n)

            case .sofa:
                // base seat
                let seat = SCNBox(width: w, height: h * 0.4, length: d * 0.75, chamferRadius: 0.12)
                seat.firstMaterial = mat(kind.scnColor, roughness: 0.55)
                let seatN = SCNNode(geometry: seat)
                seatN.position = SCNVector3(0, Float(h * 0.25), Float(d * 0.05))
                parent.addChildNode(seatN)
                // back
                let back = SCNBox(width: w, height: h * 0.55, length: d * 0.22, chamferRadius: 0.1)
                back.firstMaterial = mat(kind.scnColor.darker(), roughness: 0.55)
                let backN = SCNNode(geometry: back)
                backN.position = SCNVector3(0, Float(h * 0.45), Float(-d * 0.32))
                parent.addChildNode(backN)

            case .bed:
                let frame = SCNBox(width: w, height: h * 0.45, length: d, chamferRadius: 0.08)
                frame.firstMaterial = mat(kind.scnColor, roughness: 0.6)
                let f = SCNNode(geometry: frame)
                f.position.y = Float(h * 0.25)
                parent.addChildNode(f)
                let pillow = SCNBox(width: w * 0.85, height: h * 0.2, length: d * 0.2, chamferRadius: 0.08)
                pillow.firstMaterial = mat(UIColor.white, roughness: 0.8)
                let p = SCNNode(geometry: pillow)
                p.position = SCNVector3(0, Float(h * 0.55), Float(-d * 0.32))
                parent.addChildNode(p)

            case .lamp:
                let pole = SCNCylinder(radius: 0.06, height: h * 0.85)
                pole.firstMaterial = mat(UIColor.darkGray, roughness: 0.4)
                let poleN = SCNNode(geometry: pole)
                poleN.position.y = Float(h * 0.42)
                parent.addChildNode(poleN)
                let shade = SCNCone(topRadius: 0.15, bottomRadius: 0.55, height: h * 0.25)
                shade.firstMaterial = mat(kind.scnColor, roughness: 0.7)
                let shadeN = SCNNode(geometry: shade)
                shadeN.position.y = Float(h * 0.9)
                parent.addChildNode(shadeN)

            case .plant:
                let pot = SCNCylinder(radius: 0.35, height: 0.5)
                pot.firstMaterial = mat(UIColor.brown, roughness: 0.8)
                let potN = SCNNode(geometry: pot)
                potN.position.y = 0.25
                parent.addChildNode(potN)
                let leaves = SCNSphere(radius: 0.7)
                leaves.firstMaterial = mat(kind.scnColor, roughness: 0.7)
                let leafN = SCNNode(geometry: leaves)
                leafN.position.y = Float(h * 0.55)
                leafN.scale = SCNVector3(1, 1.3, 1)
                parent.addChildNode(leafN)

            default:
                let body = SCNBox(width: w, height: h, length: d, chamferRadius: min(0.15, h * 0.08))
                body.firstMaterial = mat(kind.scnColor, roughness: 0.55)
                let n = SCNNode(geometry: body)
                n.position.y = Float(h / 2)
                parent.addChildNode(n)
            }

            if selected {
                let ring = SCNTorus(ringRadius: max(w, d) * 0.55, pipeRadius: 0.06)
                ring.firstMaterial = mat(UIColor(red: 0.15, green: 0.42, blue: 0.95, alpha: 1), roughness: 0.3)
                let r = SCNNode(geometry: ring)
                r.position.y = 0.08
                r.eulerAngles.x = .pi / 2
                parent.addChildNode(r)
            }

            return parent
        }

        private func mat(_ color: UIColor, roughness: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.roughness.contents = roughness
            m.metalness.contents = 0.05
            m.lightingModel = .physicallyBased
            return m
        }
    }
}

private extension UIColor {
    func darker() -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: max(0, b - 0.12), alpha: a)
    }
}

// MARK: - Canvas math

private struct CanvasMetrics {
    let size: CGSize
    let roomW: Double
    let roomD: Double

    var pad: CGFloat { 24 }

    var scale: CGFloat {
        let availW = size.width - pad * 2
        let availH = size.height - pad * 2
        return min(availW / CGFloat(roomW), availH / CGFloat(roomD))
    }

    var roomWPx: CGFloat { CGFloat(roomW) * scale }
    var roomDPx: CGFloat { CGFloat(roomD) * scale }

    var origin: CGPoint {
        CGPoint(x: (size.width - roomWPx) / 2, y: (size.height - roomDPx) / 2)
    }

    func point(xFt: Double, yFt: Double) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(xFt) * scale, y: origin.y + CGFloat(yFt) * scale)
    }

    func feet(from p: CGPoint) -> (x: Double, y: Double) {
        (Double((p.x - origin.x) / scale), Double((p.y - origin.y) / scale))
    }
}
