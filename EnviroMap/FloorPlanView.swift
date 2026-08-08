import SwiftUI
import RoomPlan
import simd

/// 2D floor plan from saved CapturedRoom JSON (or stats fallback).
struct FloorPlanView: View {
    @EnvironmentObject private var store: SessionStore
    let session: RoomSession

    @State private var segments: [FloorSegment] = []
    @State private var isLoading = true
    @State private var loadNote: String?
    @State private var showMesh = false
    @State private var showWalk = false

    var body: some View {
        ZStack {
            // Match app blue theme
            LinearGradient(
                colors: [
                    AppTheme.blue.opacity(0.12),
                    AppTheme.blueSoft.opacity(0.5),
                    AppTheme.bg,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    labelChip("LiDAR walls", icon: "square.split.2x1")
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.85)
                    } else {
                        Text(segments.isEmpty ? "Stats only" : "\(segments.count) segments")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.card)
                        .shadow(color: AppTheme.blue.opacity(0.08), radius: 16, y: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )

                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Building floor plan…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    } else if segments.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.split.bottomrightquarter")
                                .font(.largeTitle)
                                .foregroundStyle(AppTheme.blue)
                            Text("No wall geometry saved")
                                .font(.headline)
                            Text(loadNote ?? "This scan has structure counts but no wall file. Stats are shown below.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            statsFallback
                        }
                    } else {
                        FloorPlanCanvas(segments: segments)
                            .padding(16)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)

                VStack(spacing: 12) {
                    Text(session.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text("\(session.wallCount) walls · \(session.doorCount) doors · \(session.windowCount) windows")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)

                    HStack(spacing: 12) {
                        Button {
                            showMesh = true
                        } label: {
                            Label("View 3D", systemImage: "cube")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            showWalk = true
                        } label: {
                            Label("Walk AR", systemImage: "figure.walk")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                                        .stroke(AppTheme.blue, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Floor plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPlanAsync() }
        .fullScreenCover(isPresented: $showMesh) {
            NavigationStack {
                RoomViewerView(session: session)
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showMesh = false }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showWalk) {
            NavigationStack {
                ARWalkView(usdzURL: store.usdzURL(for: session))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showWalk = false }
                        }
                    }
            }
        }
    }

    private var statsFallback: some View {
        HStack(spacing: 16) {
            stat("Walls", "\(session.wallCount)")
            stat("Doors", "\(session.doorCount)")
            stat("Windows", "\(session.windowCount)")
        }
        .padding(.top, 8)
    }

    private func stat(_ t: String, _ v: String) -> some View {
        VStack {
            Text(v).font(.title3.weight(.bold)).foregroundStyle(AppTheme.blue)
            Text(t).font(.caption2).foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func labelChip(_ t: String, icon: String) -> some View {
        Label(t, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.blueSoft, in: Capsule())
    }

    /// Decode CapturedRoom on a background queue so the page never freezes.
    private func loadPlanAsync() {
        isLoading = true
        let url = store.folderURL(for: session).appendingPathComponent("captured_room.json")

        DispatchQueue.global(qos: .userInitiated).async {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url)
            else {
                DispatchQueue.main.async {
                    self.segments = []
                    self.loadNote = "No captured_room.json for this scan."
                    self.isLoading = false
                }
                return
            }

            do {
                let room = try JSONDecoder().decode(CapturedRoom.self, from: data)
                let segs = FloorSegment.from(room: room)
                DispatchQueue.main.async {
                    self.segments = segs
                    self.loadNote = segs.isEmpty ? "Room decoded but no walls found." : nil
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.segments = []
                    self.loadNote = "Could not read room file: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Segments

struct FloorSegment: Identifiable {
    let id = UUID()
    let x1: CGFloat
    let z1: CGFloat
    let x2: CGFloat
    let z2: CGFloat
    let kind: Kind

    enum Kind { case wall, door, window }

    static func from(room: CapturedRoom) -> [FloorSegment] {
        var out: [FloorSegment] = []

        for w in room.walls {
            let ends = endpoints(transform: w.transform, length: w.dimensions.x)
            out.append(
                FloorSegment(
                    x1: CGFloat(ends.0.x),
                    z1: CGFloat(ends.0.z),
                    x2: CGFloat(ends.1.x),
                    z2: CGFloat(ends.1.z),
                    kind: .wall
                )
            )
        }
        for d in room.doors {
            let ends = endpoints(transform: d.transform, length: d.dimensions.x)
            out.append(
                FloorSegment(
                    x1: CGFloat(ends.0.x),
                    z1: CGFloat(ends.0.z),
                    x2: CGFloat(ends.1.x),
                    z2: CGFloat(ends.1.z),
                    kind: .door
                )
            )
        }
        for w in room.windows {
            let ends = endpoints(transform: w.transform, length: w.dimensions.x)
            out.append(
                FloorSegment(
                    x1: CGFloat(ends.0.x),
                    z1: CGFloat(ends.0.z),
                    x2: CGFloat(ends.1.x),
                    z2: CGFloat(ends.1.z),
                    kind: .window
                )
            )
        }
        return out
    }

    private static func endpoints(
        transform: simd_float4x4,
        length: Float
    ) -> (SIMD3<Float>, SIMD3<Float>) {
        let half = length / 2
        let local0 = SIMD4<Float>(-half, 0, 0, 1)
        let local1 = SIMD4<Float>(half, 0, 0, 1)
        let world0 = simd_mul(transform, local0)
        let world1 = simd_mul(transform, local1)
        return (
            SIMD3<Float>(world0.x, world0.y, world0.z),
            SIMD3<Float>(world1.x, world1.y, world1.z)
        )
    }
}

// MARK: - Canvas

struct FloorPlanCanvas: View {
    let segments: [FloorSegment]

    var body: some View {
        GeometryReader { geo in
            let bounds = Self.bounds(of: segments)
            let pad: CGFloat = 24
            let scale = min(
                (geo.size.width - pad * 2) / max(bounds.width, 0.1),
                (geo.size.height - pad * 2) / max(bounds.height, 0.1)
            )

            ZStack {
                Path { p in
                    let step: CGFloat = max(0.5 * scale, 12)
                    var x = pad
                    while x < geo.size.width - pad {
                        p.move(to: CGPoint(x: x, y: pad))
                        p.addLine(to: CGPoint(x: x, y: geo.size.height - pad))
                        x += step
                    }
                    var y = pad
                    while y < geo.size.height - pad {
                        p.move(to: CGPoint(x: pad, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width - pad, y: y))
                        y += step
                    }
                }
                .stroke(AppTheme.blue.opacity(0.08), lineWidth: 1)

                ForEach(segments) { seg in
                    Path { p in
                        let a = map(seg.x1, seg.z1, bounds: bounds, size: geo.size, scale: scale)
                        let b = map(seg.x2, seg.z2, bounds: bounds, size: geo.size, scale: scale)
                        p.move(to: a)
                        p.addLine(to: b)
                    }
                    .stroke(
                        color(for: seg.kind),
                        style: StrokeStyle(
                            lineWidth: seg.kind == .wall ? 4 : 3,
                            lineCap: .round,
                            dash: seg.kind == .window ? [6, 4] : []
                        )
                    )
                }
            }
        }
    }

    private func color(for kind: FloorSegment.Kind) -> Color {
        switch kind {
        case .wall: return AppTheme.blueDeep
        case .door: return AppTheme.blue
        case .window: return Color(red: 0.35, green: 0.7, blue: 1.0)
        }
    }

    private static func bounds(of segs: [FloorSegment]) -> CGRect {
        guard !segs.isEmpty else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minZ = CGFloat.greatestFiniteMagnitude
        var maxZ = -CGFloat.greatestFiniteMagnitude
        for s in segs {
            minX = min(minX, s.x1, s.x2)
            maxX = max(maxX, s.x1, s.x2)
            minZ = min(minZ, s.z1, s.z2)
            maxZ = max(maxZ, s.z1, s.z2)
        }
        return CGRect(x: minX, y: minZ, width: max(maxX - minX, 0.5), height: max(maxZ - minZ, 0.5))
    }

    private func map(_ x: CGFloat, _ z: CGFloat, bounds: CGRect, size: CGSize, scale: CGFloat) -> CGPoint {
        let cx = bounds.midX
        let cz = bounds.midY
        let px = (x - cx) * scale + size.width / 2
        let pz = (z - cz) * scale + size.height / 2
        return CGPoint(x: px, y: pz)
    }
}
