import SwiftUI

/// First-run intro — modern, realistic, no paywall.
struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var page = 0
    private let totalPages = 4

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top brand chip
                HStack {
                    Image(systemName: "cube.transparent.fill")
                        .font(.caption.weight(.bold))
                    Text("EnviroMap")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: Capsule())
                .padding(.top, 12)

                TabView(selection: $page) {
                    OnboardPageMeasure().tag(0)
                    OnboardPageSpaces().tag(1)
                    OnboardPageFloorPlan().tag(2)
                    OnboardPageTools().tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.28), value: page)

                // Dots
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.white : Color.white.opacity(0.28))
                            .frame(width: i == page ? 22 : 7, height: 7)
                    }
                }
                .padding(.bottom, 16)

                Button {
                    if page < totalPages - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinished()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(page < totalPages - 1 ? "Continue" : "Get started — free")
                            .font(.headline.weight(.bold))
                        Image(systemName: page < totalPages - 1 ? "arrow.right" : "sparkles")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.25, green: 0.48, blue: 1.0),
                                        AppTheme.blueDeep,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: AppTheme.blue.opacity(0.5), radius: 18, y: 8)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)

                if page < totalPages - 1 {
                    Button("Skip") { onFinished() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                } else {
                    Text("No account · No subscription · Free for now")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.16),
                    Color(red: 0.08, green: 0.10, blue: 0.22),
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Soft blue glow
            Circle()
                .fill(AppTheme.blue.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 100, y: -220)
            Circle()
                .fill(Color(red: 0.2, green: 0.4, blue: 1.0).opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: -120, y: 280)
        }
    }
}

// MARK: - Page chrome

private struct OnboardTitle: View {
    let accent: String
    let rest: String

    var body: some View {
        VStack(spacing: 6) {
            Text(accent)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.45, green: 0.7, blue: 1.0),
                            AppTheme.blue,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text(rest)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
}

private struct PhoneFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: 240, height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .shadow(color: AppTheme.blue.opacity(0.3), radius: 28, y: 14)
            )
    }
}

// MARK: - Page 1: Measure (rich room + dimensions)

private struct OnboardPageMeasure: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            PhoneFrame {
                ZStack {
                    // Room photo-like gradient background
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.58, blue: 0.62),
                            Color(red: 0.28, green: 0.30, blue: 0.34),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Perspective room walls
                    GeometryReader { g in
                        let w = g.size.width
                        let h = g.size.height

                        // Floor
                        Path { p in
                            p.move(to: CGPoint(x: w * 0.08, y: h * 0.72))
                            p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.72))
                            p.addLine(to: CGPoint(x: w * 0.98, y: h * 0.95))
                            p.addLine(to: CGPoint(x: w * 0.02, y: h * 0.95))
                            p.closeSubpath()
                        }
                        .fill(Color(white: 0.72).opacity(0.35))

                        // Back wall
                        Path { p in
                            p.move(to: CGPoint(x: w * 0.12, y: h * 0.22))
                            p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.22))
                            p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.72))
                            p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.72))
                            p.closeSubpath()
                        }
                        .fill(Color(white: 0.45).opacity(0.5))

                        // Wireframe measure lines
                        Path { p in
                            p.move(to: CGPoint(x: w * 0.12, y: h * 0.22))
                            p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.22))
                            p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.72))
                            p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.72))
                            p.closeSubpath()
                            p.move(to: CGPoint(x: w * 0.12, y: h * 0.22))
                            p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.72))
                            p.move(to: CGPoint(x: w * 0.88, y: h * 0.22))
                            p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.72))
                            // Verticals
                            p.move(to: CGPoint(x: w * 0.3, y: h * 0.22))
                            p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.72))
                            p.move(to: CGPoint(x: w * 0.7, y: h * 0.22))
                            p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.72))
                        }
                        .stroke(Color.white.opacity(0.95), lineWidth: 2)

                        // Corner dots
                        ForEach([
                            CGPoint(x: w * 0.12, y: h * 0.22),
                            CGPoint(x: w * 0.88, y: h * 0.22),
                            CGPoint(x: w * 0.08, y: h * 0.72),
                            CGPoint(x: w * 0.92, y: h * 0.72),
                            CGPoint(x: w * 0.3, y: h * 0.45),
                            CGPoint(x: w * 0.7, y: h * 0.45),
                        ], id: \.x) { pt in
                            Circle()
                                .fill(AppTheme.blue)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                .position(pt)
                        }

                        dim("14.2 ft", at: CGPoint(x: w * 0.5, y: h * 0.18))
                        dim("9.8 ft", at: CGPoint(x: w * 0.22, y: h * 0.48))
                        dim("8.1 ft", at: CGPoint(x: w * 0.82, y: h * 0.42))
                        dim("11.5 ft", at: CGPoint(x: w * 0.5, y: h * 0.78))
                    }

                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "laser.burst")
                                .font(.body.weight(.bold))
                            VStack(alignment: .leading, spacing: 0) {
                                Text("LiDAR")
                                    .font(.subheadline.weight(.bold))
                                Text("precision measure")
                                    .font(.caption2)
                                    .opacity(0.9)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [AppTheme.blue, Color(red: 0.3, green: 0.55, blue: 1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                        .padding(.bottom, 28)
                    }
                }
            }

            OnboardTitle(accent: "Measure spaces", rest: "down to the inch")
            Text("Point your Pro camera at any room. EnviroMap pulls real distances from LiDAR — not guesswork.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer(minLength: 4)
        }
    }

    private func dim(_ t: String, at p: CGPoint) -> some View {
        Text(t)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .position(p)
    }
}

// MARK: - Page 2: Realistic 3D

private struct OnboardPageSpaces: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            PhoneFrame {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.75, green: 0.82, blue: 0.9),
                            Color(red: 0.35, green: 0.42, blue: 0.52),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(spacing: 12) {
                        // Photo strip
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.6, green: 0.65, blue: 0.72),
                                        Color(red: 0.4, green: 0.45, blue: 0.52),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 100)
                            .overlay {
                                HStack(spacing: 10) {
                                    Image(systemName: "photo.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white.opacity(0.5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Live capture")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                        Text("Walking the room…")
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 36)

                        // Isometric 3D room card
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.92, green: 0.93, blue: 0.95),
                                            Color(red: 0.7, green: 0.74, blue: 0.8),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 168, height: 130)
                                .rotation3DEffect(.degrees(8), axis: (x: 1, y: 0, z: 0))
                                .shadow(color: .black.opacity(0.35), radius: 14, y: 10)

                            VStack(spacing: 8) {
                                HStack(spacing: 14) {
                                    Image(systemName: "refrigerator.fill")
                                        .foregroundStyle(AppTheme.blue.opacity(0.85))
                                    Image(systemName: "sink.fill")
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                .font(.title3)
                                HStack(spacing: 12) {
                                    Image(systemName: "sofa.fill")
                                        .font(.title2)
                                        .foregroundStyle(AppTheme.blue)
                                    Image(systemName: "lamp.desk.fill")
                                        .foregroundStyle(AppTheme.blue.opacity(0.6))
                                }
                            }
                            .offset(y: 4)
                        }

                        Text("3D mesh ready")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.black.opacity(0.4)))

                        Spacer()
                    }
                }
            }

            OnboardTitle(accent: "Build true-to-life", rest: "3D rooms")
            Text("Walk the space once. EnviroMap turns walls, doors, and furniture into a mesh you can reopen anytime.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer(minLength: 4)
        }
    }
}

// MARK: - Page 3: Floor plan (clear 2D plan visual)

private struct OnboardPageFloorPlan: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            PhoneFrame {
                ZStack {
                    Color(red: 0.07, green: 0.09, blue: 0.16)

                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Floor plan")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("Scale 1:50")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 28)
                        .padding(.bottom, 8)

                        // Full readable floor plan
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white)
                                .padding(12)

                            // Plan drawing
                            RealisticFloorPlanArt()
                                .padding(22)
                        }
                        .frame(maxHeight: .infinity)

                        // Legend
                        HStack(spacing: 12) {
                            legend(color: AppTheme.blueDeep, title: "Walls")
                            legend(color: AppTheme.blue, title: "Doors")
                            legend(color: Color(red: 0.4, green: 0.7, blue: 1), title: "Windows")
                        }
                        .padding(.bottom, 20)
                    }
                }
            }

            OnboardTitle(accent: "See the layout", rest: "as a floor plan")
            Text("Every scan becomes a clean 2D plan — walls, doors, and windows — plus the full 3D mesh.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer(minLength: 4)
        }
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 14, height: 3)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

private struct RealisticFloorPlanArt: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height

            ZStack {
                // Outer walls
                Path { p in
                    p.addRect(CGRect(x: 4, y: 4, width: w - 8, height: h - 8))
                    // Living | Bedroom split
                    p.move(to: CGPoint(x: w * 0.55, y: 4))
                    p.addLine(to: CGPoint(x: w * 0.55, y: h - 4))
                    // Kitchen divider
                    p.move(to: CGPoint(x: 4, y: h * 0.55))
                    p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.55))
                    // Bath
                    p.move(to: CGPoint(x: w * 0.55, y: h * 0.62))
                    p.addLine(to: CGPoint(x: w - 4, y: h * 0.62))
                }
                .stroke(AppTheme.blueDeep, lineWidth: 3.5)

                // Door gaps (white over walls)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 18, height: 5)
                    .position(x: w * 0.55, y: h * 0.35)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 5, height: 16)
                    .position(x: w * 0.28, y: h * 0.55)

                // Furniture outlines
                // Sofa
                RoundedRectangle(cornerRadius: 3)
                    .stroke(AppTheme.blue.opacity(0.7), lineWidth: 1.5)
                    .frame(width: w * 0.28, height: h * 0.12)
                    .position(x: w * 0.28, y: h * 0.28)
                // Table
                RoundedRectangle(cornerRadius: 2)
                    .stroke(AppTheme.blue.opacity(0.55), lineWidth: 1.2)
                    .frame(width: w * 0.16, height: h * 0.1)
                    .position(x: w * 0.28, y: h * 0.42)
                // Bed
                RoundedRectangle(cornerRadius: 3)
                    .stroke(AppTheme.blue.opacity(0.7), lineWidth: 1.5)
                    .frame(width: w * 0.28, height: h * 0.22)
                    .position(x: w * 0.76, y: h * 0.32)
                // Kitchen counters
                RoundedRectangle(cornerRadius: 2)
                    .stroke(AppTheme.blue.opacity(0.55), lineWidth: 1.2)
                    .frame(width: w * 0.38, height: h * 0.1)
                    .position(x: w * 0.28, y: h * 0.72)
                // Bath
                Circle()
                    .stroke(AppTheme.blue.opacity(0.5), lineWidth: 1.2)
                    .frame(width: 18, height: 18)
                    .position(x: w * 0.72, y: h * 0.78)

                // Room labels
                Text("Living")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.blueDeep.opacity(0.7))
                    .position(x: w * 0.28, y: h * 0.14)
                Text("Bedroom")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.blueDeep.opacity(0.7))
                    .position(x: w * 0.76, y: h * 0.14)
                Text("Kitchen")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.blueDeep.opacity(0.7))
                    .position(x: w * 0.28, y: h * 0.88)
            }
        }
    }
}

// MARK: - Page 4: Tools with emoji + descriptions (no charts)

private struct OnboardPageTools: View {
    private let features: [(emoji: String, title: String, blurb: String)] = [
        ("🏠", "Room Plan", "LiDAR scan that builds a full room mesh on your iPhone."),
        ("📏", "Ruler", "Tap two points in AR to measure real distance in feet or meters."),
        ("📐", "Level", "Digital bubble level for floors, counters, and walls."),
        ("🗺️", "Area", "Trace a floor outline and get square footage instantly."),
        ("📷", "Image → 3D", "Turn a photo into an orbitable 3D surface on-device."),
        ("✍️", "Text → 3D", "Type room sizes and generate a simple 3D box model."),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 4)

            OnboardTitle(accent: "Everything you need", rest: "in one toolkit")
                .padding(.top, 8)

            Text("Map, measure, and revisit spaces — free for now, no paywall.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(features, id: \.title) { item in
                        HStack(spacing: 14) {
                            Text(item.emoji)
                                .font(.system(size: 28))
                                .frame(width: 48, height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                Text(item.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
    }
}
