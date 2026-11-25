import SwiftUI
import AthlosCore

/// Duration and date formatting helpers. Units and date formats follow the app language (`AppLanguage`).
enum Fmt {
    /// "01:23:45"
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// "07:12" (minutes:seconds, for the break countdown)
    static func minSec(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private static var hourUnit: String { AppLanguage.isTurkish ? "sa" : "h" }
    private static var minuteUnit: String { AppLanguage.isTurkish ? "dk" : "m" }

    /// "3h 24m", "24m", "0m"  (Turkish: "3sa 24dk")
    static func hm(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds / 60))
        let h = m / 60, mm = m % 60
        if h == 0 { return "\(mm)\(minuteUnit)" }
        if mm == 0 { return "\(h)\(hourUnit)" }
        return "\(h)\(hourUnit) \(mm)\(minuteUnit)"
    }

    /// For the Completed page: "19 h", "2.5 h", "45 min"  (Turkish: "19 sa", "2,5 sa", "45 dk")
    static func hoursCompact(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        if hours < 1 { return "\(Int(seconds / 60)) \(AppLanguage.isTurkish ? "dk" : "min")" }
        let rounded = (hours * 10).rounded() / 10
        return rounded.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + (AppLanguage.isTurkish ? " sa" : " h")
    }

    /// Spoken duration for accessibility: "1 hour, 23 minutes"
    static func spoken(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .full
        var cal = Calendar.current
        cal.locale = locale
        f.calendar = cal
        return f.string(from: max(0, seconds)) ?? ""
    }

    /// Locale for dates and numbers (app language + user's region).
    static var locale: Locale { AppLanguage.locale }
    /// Number style of the language itself ("82%" in English, "%82" in Turkish), independent of region.
    static var numberLocale: Locale { Locale(identifier: AppLanguage.isTurkish ? "tr_TR" : "en_US") }

    static func date(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)) }
    static func dateTime(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale)) }
    static func time(_ d: Date) -> String { d.formatted(.dateTime.hour().minute().locale(locale)) }
    static func weekdayDate(_ d: Date) -> String { d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)) }
}

// MARK: - Color

extension Color {
    /// "#RRGGBB" → Color
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }

    /// Color → "#RRGGBB"
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X", Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }

    /// Goal reached (deep copper).
    static var goalColor: Color { Theme.brandDeep }
}

/// Project color palette (close to Apple's system colors).
enum Palette {
    static let colors = ["#A84B24", "#4E7C8A", "#0A84FF", "#30D158", "#FF9F0A", "#FF453A", "#BF5AF2", "#64D2FF", "#FFD60A", "#FF375F", "#5E5CE6", "#AC8E68", "#8E8E93", "#32ADE6"]
}

extension Project {
    var color: Color { Color(hex: colorHex) }
}
