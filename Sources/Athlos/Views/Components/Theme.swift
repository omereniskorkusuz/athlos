import SwiftUI
import AppKit
import AthlosCore

/// Athlos "Marble" theme, taken from the app icon: warm marble ivory (light) or night charcoal (dark),
/// gold from the icon's ring, serif (New York) display type like the icon's "A".
/// Every color adapts to the window's appearance, which Settings → Appearance can force.
enum Theme {
    // MARK: Surfaces
    /// Page background.
    static let canvas = Color(light: 0xF6F1E7, dark: 0x13110D)
    /// Sidebar / secondary panels.
    static let sidebar = Color(light: 0xECE4D4, dark: 0x1A1712)
    /// Cards and raised rows.
    static let card = Color(light: 0xFFFCF6, dark: 0x1E1A14)
    /// Inputs and wells inside cards.
    static let well = Color(light: 0xF8F3EA, dark: 0x16130F)
    /// Hairline borders.
    static let line = Color(light: 0xE2D7C2, dark: 0x2E281F)
    /// Empty part of bars and rings.
    static let track = Color(light: 0xE6DCC8, dark: 0x2C261D)

    // MARK: Ink
    static let ink = Color(light: 0x1C1813, dark: 0xF3EBDC)
    static let inkSecondary = Color(light: 0x6B6253, dark: 0xA99F8B)
    static let inkTertiary = Color(light: 0x9A8E78, dark: 0x6E6656)

    // MARK: Gold (from the icon ring #F2D58F → #D4AF6A → #A97F3C)
    /// Gold fills: bars, rings, dots.
    static let gold = Color(light: 0xC9A45C, dark: 0xD4AF6A)
    static let goldBright = Color(hex: "#F2D58F")
    static let goldDeep = Color(hex: "#A97F3C")
    /// Gold text and icons (darker in light mode so it stays readable on ivory).
    static let goldText = Color(light: 0x7A5A22, dark: 0xE3C27A)
    /// Soft gold chip background.
    static let goldSoft = Color(light: 0xF3E4C2, dark: 0x332A19)
    /// System accent (toggles, selections, prominent buttons with white text).
    static let accent = Color(light: 0x8C6A2E, dark: 0xB88D46)

    // MARK: States
    /// Break time: a calm sage that sits next to gold.
    static let rest = Color(light: 0x5E8275, dark: 0x8DB5A6)
    static let paused = Color(light: 0x9A8E78, dark: 0x8F8676)
    static let danger = Color(light: 0xB3412F, dark: 0xE07A62)

    // MARK: Primary button (dark ink pill in light mode, gold pill in dark mode)
    static let primaryFill = Color(light: 0x1C1813, dark: 0xD8B46E)
    static let onPrimary = Color(light: 0xFBF6EC, dark: 0x17120A)

    /// Ring / bar gradient.
    static var goldGradient: LinearGradient {
        LinearGradient(colors: [goldDeep, gold, goldBright], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Type
    /// Serif display type (New York) — page titles, big numbers.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Card / section headings.
    static let heading = Font.system(size: 19, weight: .semibold, design: .serif)
    /// Small caps-like label ("WORKING", "TODAY").
    static let eyebrow = Font.system(size: 11, weight: .semibold)

    /// Applies the chosen appearance to every window, popover and alert of the app.
    @MainActor
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension AppearanceMode {
    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }
}

extension Color {
    /// A color with a light and a dark variant (0xRRGGBB).
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Building blocks

extension View {
    /// Marble card: ivory (or night) surface with a hairline border.
    func athlosCard(radius: CGFloat = 16) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// Page background for a detail column (also hides the default scroll/form backgrounds).
    func athlosPage() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.canvas)
    }
}

/// Main action: a pill in ink (light) or gold (dark).
struct PrimaryPillStyle: ButtonStyle {
    var minWidth: CGFloat = 120
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.onPrimary)
            .frame(minWidth: minWidth)
            .padding(.horizontal, 18).frame(height: 44)
            .background(Theme.primaryFill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Secondary action: an outlined marble pill.
struct SecondaryPillStyle: ButtonStyle {
    var minWidth: CGFloat = 120
    var tint: Color = Theme.ink
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint)
            .frame(minWidth: minWidth)
            .padding(.horizontal, 18).frame(height: 44)
            .background(configuration.isPressed ? Theme.well : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

/// Uppercase, letter-spaced label.
struct Eyebrow: View {
    let text: LocalizedStringKey
    var color: Color = Theme.inkSecondary

    init(_ text: LocalizedStringKey, color: Color = Theme.inkSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Theme.eyebrow)
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
