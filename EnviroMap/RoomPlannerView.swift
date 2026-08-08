import SwiftUI
import RoomPlan
import simd

// MARK: - Catalog & layout models

enum FurnitureKind: String, CaseIterable, Identifiable, Codable {
    case sofa, armchair, coffeeTable, diningTable, chair, bed, nightstand
    case desk, bookshelf, tvStand, plant, lamp, rug, fridge, door

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sofa: return "Sofa"
        case .armchair: return "Chair"
        case .coffeeTable: return "Coffee table"
        case .diningTable: return "Dining table"
        case .chair: return "Side chair"
        case .bed: return "Bed"
        case .nightstand: return "Nightstand"
        case .desk: return "Desk"
        case .bookshelf: return "Bookshelf"
        case .tvStand: return "TV stand"
        case .plant: return "Plant"
        case .lamp: return "Lamp"
        case .rug: return "Rug"
        case .fridge: return "Fridge"
        case .door: return "Door mark"
        }
    }

    var emoji: String {
        switch self {
        case .sofa: return "🛋️"
        case .armchair: return "🪑"
        case .coffeeTable: return "🪵"
        case .diningTable: return "🍽️"
        case .chair: return "💺"
        case .bed: return "🛏️"
        case .nightstand: return "📦"
        case .desk: return "🖥️"
        case .bookshelf: return "📚"
        case .tvStand: return "📺"
        case .plant: return "🪴"
        case .lamp: return "💡"
        case .rug: return "🟦"
        case .fridge: return "🧊"
        case .door: return "🚪"
        }
    }

    /// Width × depth in feet (approx real sizes)
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
        case .door: return CGSize(width: 3.0, height: 0.5)
        }
    }

    var color: Color {
        switch self {
        case .sofa: return Color(red: 0.25, green: 0.45, blue: 0.9)
        case .armchair: return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .coffeeTable, .diningTable, .desk, .tvStand, .nightstand:
            return Color(red: 0.55, green: 0.4, blue: 0.28)
        case .chair: return Color(red: 0.4, green: 0.5, blue: 0.65)
        case .bed: return Color(red: 0.45, green: 0.55, blue: 0.85)
        case .bookshelf: return Color(red: 0.5, green: 0.35, blue: 0.25)
        case .plant: return Color(red: 0.25, green: 0.65, blue: 0.4)
        case .lamp: return Color(red: 0.95, green: 0.8, blue: 0.3)
        case .rug: return Color(red: 0.7, green: 0.78, blue: 0.95).opacity(0.85)
        case .fridge: return Color(red: 0.75, green: 0.8, blue: 0.85)
        case .door: return Color(red: 0.3, green: 0.5, blue: 0.9)
        }
    }
}

struct PlacedFurniture: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: FurnitureKind
    /// Position in feet from room origin (bottom-left of room)
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
    /// Optional wall segments in feet (from LiDAR), local coords
    var wallSegments: [WallSeg]

    struct WallSeg: Codable, Equatable {
        var x1: Double, y1: Double, x2: Double, y2: Double
    }

    static func empty(width: Double = 14, depth: Double = 16) -> RoomLayout {
        RoomLayout(roomWidthFt: width, roomDepthFt: depth, items: [], wallSegments: [])
    }
}

// MARK: - Planner

struct RoomPlannerView: View {
    @EnvironmentObject private var store: SessionStore

    /// Optional LiDAR session — if set, tries to load walls + save layout beside scan
    var session: RoomSession? = nil

    @State private var layout = RoomLayout.empty()
    @State private var selectedId: UUID?
    @State private var showCatalog = true
    @State private var showScanner = false
    @State private var showResize = false
    @State private var widthText = "14"
    @State private var depthText = "16"
    @State private var toast: String?

    private var storageKey: String {
        if let session { return "enviromap.layout.\(session.id.uuidString)" }
        return "enviromap.layout.blank"
    }

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let selected = selectedItem {
                    itemToolbar(selected)
                }

                if showCatalog {
                    catalogBar
                }
            }
        }
        .navigationTitle(session?.name ?? "Room Planner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showCatalog.toggle()
                    } label: {
                        Label(showCatalog ? "Hide catalog" : "Show catalog", systemImage: "square.grid.2x2")
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
                            Label("Scan real room (LiDAR)", systemImage: "camera.viewfinder")
                        }
                    }
                    Button(role: .destructive) {
                        clearAll()
                    } label: {
                        Label("Clear furniture", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.blue)
                }
            }
        }
        .onAppear {
            loadLayout()
            if let session {
                importWallsIfNeeded(from: session)
            }
        }
        .onChange(of: layout) { _ in
            saveLayout()
        }
        .alert("Room size (feet)", isPresented: $showResize) {
            TextField("Width ft", text: $widthText)
                .keyboardType(.decimalPad)
            TextField("Depth ft", text: $depthText)
                .keyboardType(.decimalPad)
            Button("Apply") { applyResize() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set the empty room footprint. Furniture stays; walls from LiDAR stay if present.")
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScanFlowView()
                .environmentObject(store)
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(AppTheme.blueDeep))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 10) {
            Label(
                String(format: "%.0f × %.0f ft", layout.roomWidthFt, layout.roomDepthFt),
                systemImage: "ruler"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.blueSoft, in: Capsule())

            if !layout.wallSegments.isEmpty {
                Label("LiDAR walls", systemImage: "square.split.bottomrightquarter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.blueDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.blueSoft.opacity(0.7), in: Capsule())
            }

            Spacer()

            Text("\(layout.items.count) items")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let metrics = CanvasMetrics(
                size: geo.size,
                roomW: layout.roomWidthFt,
                roomD: layout.roomDepthFt
            )

            ZStack {
                // Floor
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: AppTheme.blue.opacity(0.08), radius: 16, y: 6)
                    .padding(12)

                // Grid + walls + furniture
                ZStack {
                    gridLayer(metrics)
                    wallsLayer(metrics)
                    roomOutline(metrics)

                    ForEach(layout.items) { item in
                        furnitureView(item, metrics: metrics)
                    }
                }
                .padding(12)

                // Tap empty area to deselect
                Color.clear
                    .contentShape(Rectangle())
                    .padding(12)
                    .onTapGesture { selectedId = nil }
            }
            .onDrop(of: [.text], isTargeted: nil) { _ in false }
        }
    }

    private func gridLayer(_ m: CanvasMetrics) -> some View {
        Path { p in
            let step = m.scale // 1 ft
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
        .stroke(AppTheme.blueSoft, lineWidth: 1)
    }

    private func roomOutline(_ m: CanvasMetrics) -> some View {
        Rectangle()
            .stroke(AppTheme.blueDeep, lineWidth: 3)
            .frame(width: m.roomWPx, height: m.roomDPx)
            .position(x: m.origin.x + m.roomWPx / 2, y: m.origin.y + m.roomDPx / 2)
    }

    private func wallsLayer(_ m: CanvasMetrics) -> some View {
        Path { p in
            for w in layout.wallSegments {
                let a = m.point(xFt: w.x1, yFt: w.y1)
                let b = m.point(xFt: w.x2, yFt: w.y2)
                p.move(to: a)
                p.addLine(to: b)
            }
        }
        .stroke(AppTheme.blueDeep, style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }

    private func furnitureView(_ item: PlacedFurniture, metrics m: CanvasMetrics) -> some View {
        let size = item.kind.sizeFt
        let w = size.width * m.scale
        let h = size.height * m.scale
        let center = m.point(xFt: item.xFt, yFt: item.yFt)
        let selected = item.id == selectedId

        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(item.kind.color.opacity(item.kind == .rug ? 0.45 : 0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected ? AppTheme.blue : .white.opacity(0.6), lineWidth: selected ? 3 : 1)
                )
                .frame(width: w, height: h)

            VStack(spacing: 2) {
                Text(item.kind.emoji)
                    .font(.system(size: min(22, min(w, h) * 0.35)))
                if min(w, h) > 36 {
                    Text(item.kind.title)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(item.rotationDeg))
        .position(center)
        .shadow(color: .black.opacity(0.12), radius: selected ? 8 : 3, y: 2)
        .gesture(
            DragGesture()
                .onChanged { value in
                    selectedId = item.id
                    if let idx = layout.items.firstIndex(where: { $0.id == item.id }) {
                        let ft = m.feet(from: value.location)
                        layout.items[idx].xFt = min(max(ft.x, 0.5), layout.roomWidthFt - 0.5)
                        layout.items[idx].yFt = min(max(ft.y, 0.5), layout.roomDepthFt - 0.5)
                    }
                }
        )
        .onTapGesture {
            selectedId = item.id
        }
        .zIndex(item.kind == .rug ? 0 : (selected ? 10 : 1))
    }

    // MARK: Item toolbar

    private var selectedItem: PlacedFurniture? {
        guard let selectedId else { return nil }
        return layout.items.first { $0.id == selectedId }
    }

    private func itemToolbar(_ item: PlacedFurniture) -> some View {
        HStack(spacing: 12) {
            Text("\(item.kind.emoji) \(item.kind.title)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.text)

            Spacer()

            Button {
                rotateSelected(-15)
            } label: {
                Image(systemName: "rotate.left")
            }
            Button {
                rotateSelected(15)
            } label: {
                Image(systemName: "rotate.right")
            }
            Button(role: .destructive) {
                deleteSelected()
            } label: {
                Image(systemName: "trash")
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(AppTheme.blue)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.card)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: Catalog

    private var catalogBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Furniture catalog")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Text("Tap to place")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FurnitureKind.allCases) { kind in
                        Button {
                            place(kind)
                        } label: {
                            VStack(spacing: 6) {
                                Text(kind.emoji)
                                    .font(.title2)
                                    .frame(width: 52, height: 40)
                                Text(kind.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppTheme.text)
                                    .lineLimit(1)
                                Text(String(format: "%.0f×%.0f′", kind.sizeFt.width, kind.sizeFt.height))
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            .frame(width: 76)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(
            AppTheme.card
                .shadow(color: .black.opacity(0.06), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: Actions

    private func place(_ kind: FurnitureKind) {
        let x = layout.roomWidthFt / 2
        let y = layout.roomDepthFt / 2
        // slight offset so stacked taps don't fully overlap
        let jitter = Double(layout.items.count % 5) * 0.4
        var item = PlacedFurniture.make(kind, at: x + jitter, y: y + jitter)
        // keep in bounds
        item.xFt = min(max(item.xFt, 1), layout.roomWidthFt - 1)
        item.yFt = min(max(item.yFt, 1), layout.roomDepthFt - 1)
        layout.items.append(item)
        selectedId = item.id
        flash("Added \(kind.title)")
    }

    private func rotateSelected(_ deg: Double) {
        guard let selectedId,
              let idx = layout.items.firstIndex(where: { $0.id == selectedId }) else { return }
        layout.items[idx].rotationDeg += deg
    }

    private func deleteSelected() {
        guard let selectedId else { return }
        layout.items.removeAll { $0.id == selectedId }
        self.selectedId = nil
    }

    private func clearAll() {
        layout.items = []
        selectedId = nil
        flash("Furniture cleared")
    }

    private func applyResize() {
        let w = Double(widthText) ?? layout.roomWidthFt
        let d = Double(depthText) ?? layout.roomDepthFt
        layout.roomWidthFt = min(max(w, 6), 60)
        layout.roomDepthFt = min(max(d, 6), 60)
        flash("Room set to \(Int(layout.roomWidthFt))×\(Int(layout.roomDepthFt)) ft")
    }

    private func flash(_ msg: String) {
        withAnimation { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { toast = nil }
        }
    }

    // MARK: Persist

    private func saveLayout() {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
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
        // Only import if we don't already have walls saved in layout
        guard layout.wallSegments.isEmpty else { return }

        let url = store.folderURL(for: session).appendingPathComponent("captured_room.json")
        guard let data = try? Data(contentsOf: url),
              let room = try? JSONDecoder().decode(CapturedRoom.self, from: data)
        else { return }

        var segs: [RoomLayout.WallSeg] = []
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude

        for w in room.walls {
            let ends = wallEndpoints(transform: w.transform, length: w.dimensions.x)
            let x1 = Double(ends.0.x), z1 = Double(ends.0.z)
            let x2 = Double(ends.1.x), z2 = Double(ends.1.z)
            segs.append(.init(x1: x1, y1: z1, x2: x2, y2: z2))
            minX = min(minX, x1, x2); maxX = max(maxX, x1, x2)
            minZ = min(minZ, z1, z2); maxZ = max(maxZ, z1, z2)
        }

        guard !segs.isEmpty, minX.isFinite else { return }

        // Convert meters → feet, shift to positive origin
        let m2ft = 3.28084
        let pad = 1.0 // ft
        var shifted: [RoomLayout.WallSeg] = []
        for s in segs {
            shifted.append(.init(
                x1: (s.x1 - minX) * m2ft + pad,
                y1: (s.y1 - minZ) * m2ft + pad,
                x2: (s.x2 - minX) * m2ft + pad,
                y2: (s.y2 - minZ) * m2ft + pad
            ))
        }

        let width = max(8, (maxX - minX) * m2ft + pad * 2)
        let depth = max(8, (maxZ - minZ) * m2ft + pad * 2)

        layout.roomWidthFt = width
        layout.roomDepthFt = depth
        layout.wallSegments = shifted
        saveLayout()
        flash("LiDAR walls loaded")
    }

    private func wallEndpoints(transform: simd_float4x4, length: Float) -> (SIMD3<Float>, SIMD3<Float>) {
        let half = length / 2
        let local0 = SIMD4<Float>(-half, 0, 0, 1)
        let local1 = SIMD4<Float>(half, 0, 0, 1)
        let world0 = simd_mul(transform, local0)
        let world1 = simd_mul(transform, local1)
        return (
            SIMD3(world0.x, world0.y, world0.z),
            SIMD3(world1.x, world1.y, world1.z)
        )
    }
}

// MARK: - Canvas math

private struct CanvasMetrics {
    let size: CGSize
    let roomW: Double
    let roomD: Double

    var pad: CGFloat { 28 }

    var scale: CGFloat {
        let availW = size.width - pad * 2
        let availH = size.height - pad * 2
        return min(availW / CGFloat(roomW), availH / CGFloat(roomD))
    }

    var roomWPx: CGFloat { CGFloat(roomW) * scale }
    var roomDPx: CGFloat { CGFloat(roomD) * scale }

    var origin: CGPoint {
        CGPoint(
            x: (size.width - roomWPx) / 2,
            y: (size.height - roomDPx) / 2
        )
    }

    func point(xFt: Double, yFt: Double) -> CGPoint {
        CGPoint(
            x: origin.x + CGFloat(xFt) * scale,
            y: origin.y + CGFloat(yFt) * scale
        )
    }

    func feet(from p: CGPoint) -> (x: Double, y: Double) {
        (
            Double((p.x - origin.x) / scale),
            Double((p.y - origin.y) / scale)
        )
    }
}
