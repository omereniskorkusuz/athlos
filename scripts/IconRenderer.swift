// Draws the Athlos app icon (1024×1024 PNG) — the "time ring" design:
// dark background, a gold ring 80% full like the daily goal bar, a serif "A" in the middle, a four-pointed star where the ring starts.
// Usage: swift scripts/IconRenderer.swift output.png
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Flip the y axis to draw with the same coordinates as the SVG (0,0 top left).
ctx.translateBy(x: 0, y: 1024)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// 1) macOS icon grid: 824 pt rounded square with a shadow
let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: rgb(0x000000, 0.4))
ctx.addPath(tile); ctx.setFillColor(rgb(0x121212)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tile); ctx.clip()
// A very soft warm light on the background (from the top)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let glow = CGGradient(colorsSpace: space, colors: [rgb(0x2A241B), rgb(0x121212)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 300), startRadius: 0, endCenter: CGPoint(x: 512, y: 300), endRadius: 620, options: [.drawsAfterEndLocation])

// 2) Ring: dark track + 80% gold arc (clockwise, starting at the top)
let center = CGPoint(x: 512, y: 512)
ctx.setLineWidth(44)
ctx.setStrokeColor(rgb(0x2C2720))
ctx.addEllipse(in: CGRect(x: 212, y: 212, width: 600, height: 600)); ctx.strokePath()

ctx.setLineCap(.round)
let start = -CGFloat.pi / 2
ctx.addArc(center: center, radius: 300, startAngle: start, endAngle: start + 0.8 * 2 * .pi, clockwise: false)
ctx.replacePathWithStrokedPath()
ctx.clip()
let gold = CGGradient(colorsSpace: space, colors: [rgb(0xF2D58F), rgb(0xD4AF6A), rgb(0xA97F3C)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(gold, start: CGPoint(x: 300, y: 200), end: CGPoint(x: 760, y: 820), options: [])
ctx.resetClip()
ctx.addPath(tile); ctx.clip()

// 3) Serif "A" (same path as the SVG; scale 0.66, centered at 512,520)
let a = CGMutablePath()
a.addLines(between: [(512, 280), (688, 700), (720, 700), (720, 716), (600, 716), (600, 700), (630, 700), (594, 612),
                     (430, 612), (394, 700), (424, 700), (424, 716), (304, 716), (304, 700), (336, 700)].map { CGPoint(x: $0.0, y: $0.1) })
a.closeSubpath()
a.addLines(between: [CGPoint(x: 512, y: 418), CGPoint(x: 572, y: 566), CGPoint(x: 452, y: 566)])
a.closeSubpath()
var aTransform = CGAffineTransform(translationX: 512, y: 520).scaledBy(x: 0.66, y: 0.66).translatedBy(x: -512, y: -500)
ctx.saveGState()
ctx.addPath(a.copy(using: &aTransform)!)
ctx.clip(using: .evenOdd)
let marble = CGGradient(colorsSpace: space, colors: [rgb(0xFBF6EC), rgb(0xE6DAC4)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(marble, start: CGPoint(x: 512, y: 340), end: CGPoint(x: 512, y: 700), options: [])
ctx.restoreGState()

// 4) Four-pointed star (at the start of the ring) + a soft glow
let star = CGMutablePath()
let pts: [(CGFloat, CGFloat)] = [(0, -70), (13, -13), (70, 0), (13, 13), (0, 70), (-13, 13), (-70, 0), (-13, -13)]
star.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
star.closeSubpath()
var sTransform = CGAffineTransform(translationX: 512, y: 212).scaledBy(x: 0.75, y: 0.75)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 28, color: rgb(0xFFE7A8, 0.75))
ctx.addPath(star.copy(using: &sTransform)!)
ctx.setFillColor(rgb(0xFFEBB5))
ctx.fillPath()
ctx.restoreGState()

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("ikon: \(out)")
