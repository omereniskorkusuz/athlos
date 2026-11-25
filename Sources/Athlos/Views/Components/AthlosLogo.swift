import SwiftUI

/// The Athlos mark drawn in code (same geometry as `scripts/IconRenderer.swift`):
/// night tile, gold ring 80% full, marble serif "A", four-pointed star where the ring starts.
/// Drawn as vectors, so it stays sharp at any size.
struct AthlosLogo: View {
    var size: CGFloat = 40
    /// Shows the dark rounded tile behind the ring (off: just the ring, the A and the star).
    var tile = true

    var body: some View {
        Canvas { ctx, canvasSize in
            // The icon is designed on a 1024 grid with the tile at 100…924.
            let s = canvasSize.width / 824
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -100, y: -100)

            let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
            let tilePath = Path(roundedRect: tileRect, cornerRadius: 185, style: .continuous)
            if tile {
                ctx.fill(tilePath, with: .radialGradient(Gradient(colors: [Color(hex: "#2A241B"), Color(hex: "#121212")]),
                                                         center: CGPoint(x: 512, y: 300), startRadius: 0, endRadius: 620))
                ctx.clip(to: tilePath)
            }

            // Ring: track + 80% gold arc, clockwise from the top.
            let center = CGPoint(x: 512, y: 512)
            ctx.stroke(Path(ellipseIn: CGRect(x: 212, y: 212, width: 600, height: 600)),
                       with: .color(tile ? Color(hex: "#2C2720") : Color(hex: "#2C2720").opacity(0.25)), lineWidth: 44)
            var arc = Path()
            arc.addArc(center: center, radius: 300, startAngle: .degrees(-90), endAngle: .degrees(-90 + 288), clockwise: false)
            ctx.stroke(arc, with: .linearGradient(Gradient(colors: [Color(hex: "#F2D58F"), Color(hex: "#D4AF6A"), Color(hex: "#A97F3C")]),
                                                 startPoint: CGPoint(x: 300, y: 200), endPoint: CGPoint(x: 760, y: 820)),
                       style: StrokeStyle(lineWidth: 44, lineCap: .round))

            // Serif "A" (scaled 0.66 around 512,520), outer shape + counter.
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 512 + (x - 512) * 0.66, y: 520 + (y - 500) * 0.66) }
            var a = Path()
            a.addLines([p(512, 280), p(688, 700), p(720, 700), p(720, 716), p(600, 716), p(600, 700), p(630, 700), p(594, 612),
                        p(430, 612), p(394, 700), p(424, 700), p(424, 716), p(304, 716), p(304, 700), p(336, 700)])
            a.closeSubpath()
            a.addLines([p(512, 418), p(572, 566), p(452, 566)])
            a.closeSubpath()
            let marble = tile ? [Color(hex: "#FBF6EC"), Color(hex: "#E6DAC4")] : [Color(hex: "#A97F3C"), Color(hex: "#7A5A22")]
            ctx.fill(a, with: .linearGradient(Gradient(colors: marble), startPoint: CGPoint(x: 512, y: 374), endPoint: CGPoint(x: 512, y: 663)),
                     style: FillStyle(eoFill: true))

            // Star + soft glow at the start of the ring.
            ctx.fill(Path(ellipseIn: CGRect(x: 432, y: 132, width: 160, height: 160)),
                     with: .radialGradient(Gradient(colors: [Color(hex: "#FFE7A8").opacity(0.8), Color(hex: "#FFE7A8").opacity(0)]),
                                           center: CGPoint(x: 512, y: 212), startRadius: 0, endRadius: 80))
            let pts: [(CGFloat, CGFloat)] = [(0, -70), (13, -13), (70, 0), (13, 13), (0, 70), (-13, 13), (-70, 0), (-13, -13)]
            var star = Path()
            star.addLines(pts.map { CGPoint(x: 512 + $0.0 * 0.75, y: 212 + $0.1 * 0.75) })
            star.closeSubpath()
            ctx.fill(star, with: .color(Color(hex: "#FFEBB5")))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Athlos")
    }
}

/// Logo + "Athlos" wordmark in serif, for the sidebar and the welcome screen.
struct AthlosBrand: View {
    var logoSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 11) {
            AthlosLogo(size: logoSize)
                .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
            Text(verbatim: "Athlos")
                .font(Theme.display(logoSize * 0.66, weight: .bold))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Athlos")
    }
}
