import AppKit
import SwiftUI

/// In-app language choice. English is the development language; Turkish is bundled as a second language.
/// The choice is applied through the app's own `AppleLanguages` default, so it takes effect on the next launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, tr

    var id: String { rawValue }

    private static let key = "app.language"

    /// Language names are shown in their own language and never translated.
    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .en: "English"
        case .tr: "Türkçe"
        }
    }

    /// The saved choice (what the picker shows).
    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    /// Saves the choice. Returns true if a restart is needed to apply it.
    @discardableResult
    static func select(_ lang: AppLanguage) -> Bool {
        let before = effectiveCode
        UserDefaults.standard.set(lang.rawValue, forKey: key)
        switch lang {
        case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .en, .tr: UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
        }
        let wanted = lang == .system ? (Locale.preferredLanguages.first.map { $0.hasPrefix("tr") ? "tr" : "en" } ?? "en") : lang.rawValue
        return wanted != before
    }

    /// The language the running app actually uses ("en" or "tr").
    static var effectiveCode: String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("tr") == true ? "tr" : "en"
    }

    static var isTurkish: Bool { effectiveCode == "tr" }

    /// Locale for dates and numbers: the app language with the user's region.
    static var locale: Locale {
        Locale(identifier: "\(effectiveCode)_\(Locale.current.region?.identifier ?? (isTurkish ? "TR" : "US"))")
    }

    /// Restarts Athlos so a new language takes effect.
    @MainActor
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
