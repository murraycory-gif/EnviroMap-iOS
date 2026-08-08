import SwiftUI

/// Brand mark: wireframe cube + scan slash + EnviroMap wordmark (light theme blues).
struct EnviroMapLogo: View {
    var showWordmark: Bool = true
    var height: CGFloat = 44

    var body: some View {
        HStack(spacing: height * 0.28) {
            mark
                .frame(width: height * 1.05, height: height * 1.05)

            if showWordmark {
                wordmark
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EnviroMap")
    }

    private var mark: some View {
        ZStack {
            // Soft blue glow plate
            RoundedRectangle(cornerRadius: height * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.blueSoft,
                            AppTheme.blue.opacity(0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Isometric-ish wire cube
            WireCubeShape()
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.blue, Color(red: 0.35, green: 0.65, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: max(1.5, height * 0.045), lineJoin: .round)
                )
                .padding(height * 0.18)

            // Scan slash
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            AppTheme.blue,
                            Color(red: 0.4, green: 0.75, blue: 1.0),
                            Color.white.opacity(0.3),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .frame(width: height * 0.08, height: height * 1.05)
                .rotationEffect(.degrees(-38))
                .shadow(color: AppTheme.blue.opacity(0.55), radius: 6, y: 0)

            // Tiny lidar dots
            Circle()
                .fill(AppTheme.blue)
                .frame(width: height * 0.06, height: height * 0.06)
                .offset(x: -height * 0.28, y: -height * 0.32)
            Circle()
                .fill(AppTheme.blue.opacity(0.7))
                .frame(width: height * 0.045, height: height * 0.045)
                .offset(x: height * 0.3, y: height * 0.28)
        }
    }

    private var wordmark: some View {
        HStack(spacing: 0) {
            Text("Enviro")
                .foregroundStyle(AppTheme.text)
            Text("Map")
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.blue, Color(red: 0.4, green: 0.7, blue: 1.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .font(.system(size: height * 0.52, weight: .bold, design: .rounded))
        .tracking(-0.6)
    }
}

/// Simple isometric cube outline (front + top + side).
private struct WireCubeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let ox = w * 0.18
        let oy = h * 0.12

        // Front face
        let fl = CGPoint(x: rect.minX + ox * 0.4, y: rect.midY + oy)
        let fr = CGPoint(x: rect.midX + ox * 0.15, y: rect.midY + oy * 1.4)
        let br = CGPoint(x: rect.midX + ox * 0.15, y: rect.maxY - oy * 0.2)
        let bl = CGPoint(x: rect.minX + ox * 0.4, y: rect.maxY - oy * 0.9)

        // Top / depth
        let flTop = CGPoint(x: fl.x + ox, y: fl.y - oy * 1.6)
        let frTop = CGPoint(x: fr.x + ox, y: fr.y - oy * 1.6)
        let brTop = CGPoint(x: br.x + ox * 0.85, y: br.y - oy * 1.5)

        var p = Path()
        // Front
        p.move(to: fl)
        p.addLine(to: fr)
        p.addLine(to: br)
        p.addLine(to: bl)
        p.closeSubpath()
        // Top
        p.move(to: fl)
        p.addLine(to: flTop)
        p.addLine(to: frTop)
        p.addLine(to: fr)
        // Side
        p.move(to: fr)
        p.addLine(to: frTop)
        p.addLine(to: brTop)
        p.addLine(to: br)
        // Inner maze-ish detail
        let m1 = CGPoint(x: (fl.x + fr.x) / 2, y: (fl.y + fr.y) / 2 + h * 0.08)
        let m2 = CGPoint(x: m1.x, y: m1.y + h * 0.22)
        p.move(to: CGPoint(x: fl.x + w * 0.12, y: fl.y + h * 0.12))
        p.addLine(to: m1)
        p.addLine(to: m2)
        p.addLine(to: CGPoint(x: br.x - w * 0.08, y: br.y - h * 0.12))
        return p
    }
}

#Preview {
    VStack(spacing: 32) {
        EnviroMapLogo(height: 56)
        EnviroMapLogo(showWordmark: false, height: 72)
    }
    .padding()
    .background(AppTheme.bg)
}
