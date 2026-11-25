import SwiftUI
import AppKit
import AthlosCore

/// Athlos "Copper" theme: neutral graphite surfaces, copper accent, steel-blue for breaks.
/// Gold stays only in the logo (and its four-pointed star). Serif (New York) display type like the icon's "A".
/// Every color adapts to the window's appearance, which Settings → Appearance can force.
enum Theme {
    // MARK: Surfaces
    /// Page background.
    static let canvas = Color(light: 0xF5F5F4, dark: 0x101012)
    /// Icon rail (sidebar).
    static let rail = Color(light: 0xEBEBEA, dark: 0x0B0B0C)
    /// Side panels (Today panel, project tree).
    static let panel = Color(light: 0xFFFFFF, dark: 0x141416)
    /// Cards and raised rows.
    static let card = Color(light: 0xFFFFFF, dark: 0x19191C)
    /// Inputs and wells inside cards.
    static let well = Color(light: 0xF8F8F7, dark: 0x121214)
    /// Hairline borders.
    static let line = Color(light: 0xE0DFDD, dark: 0x26262A)
    /// Empty part of bars and rings.
    static let track = Color(light: 0xE7E6E4, dark: 0x232327)

    // MARK: Ink
    static let ink = Color(light: 0x18181B, dark: 0xEDEDEF)
    static let inkSecondary = Color(light: 0x5F5F67, dark: 0x9A9AA3)
    static let inkTertiary = Color(light: 0x8E8E96, dark: 0x66666E)

    // MARK: Brand (copper)
    /// Copper fills: bars, rings, dots, the main button.
    static let brand = Color(light: 0xA84B24, dark: 0xE07A4F)
    /// Stronger copper: goal days in the calendar, the reached goal.
    static let brandDeep = Color(light: 0x7E3518, dark: 0xF4A27A)
    /// Lighter copper for gradients.
    static let brandBright = Color(light: 0xD27A4E, dark: 0xF3B08C)
    /// Copper text and icons.
    static let brandText = Color(light: 0x9C4420, dark: 0xEE9470)
    /// Soft copper chip / selected background.
    static let brandSoft = Color(light: 0xF6E6DE, dark: 0x2A1A13)
    /// System accent (toggles, selections, prominent buttons with white text).
    static let accent = Color(light: 0xA84B24, dark: 0xC8603A)
    /// The logo's gold, used only for the star mark.
    static let star = Color(hex: "#D4AF6A")

    // MARK: States
    /// Break time: steel blue.
    static let rest = Color(light: 0x4E7C8A, dark: 0x7FB0BE)
    static let paused = Color(light: 0x8E8E96, dark: 0x7A7A82)
    static let danger = Color(light: 0xB3261E, dark: 0xF2867A)

    // MARK: Primary button
    static let primaryFill = brand
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x170A04)

    /// Bar / ring gradient.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, brandBright], startPoint: .leading, endPoint: .trailing)
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
