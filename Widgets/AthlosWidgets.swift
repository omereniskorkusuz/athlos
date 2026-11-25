import WidgetKit
import SwiftUI
import AppIntents
import AthlosCore

// MARK: - Bundle

/// Athlos widgets for the macOS widget gallery.
@main
struct AthlosWidgetBundle: WidgetBundle {
    var body: some Widget {
        HeatmapWidget()
        TimerWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snap = WidgetSnapshot.load() ?? .preview
        completion(SnapshotEntry(date: Date(), snapshot: snap, isPlaceholder: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snap = WidgetSnapshot.load() ?? .empty
        var entries = [SnapshotEntry(date: now, snapshot: snap, isPlaceholder: false)]
        // Switch the view when the break ends
        if let end = snap.breakEndsAt, end > now {
            var after = snap
            after.phase = .paused
            after.breakEndsAt = nil
            entries.append(SnapshotEntry(date: end, snapshot: after, isPlaceholder: false))
        }
        // The app reloads on changes anyway; still refresh at midnight and every 15 min.
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: entries, policy: .after(min(midnight, now.addingTimeInterval(900)))))
    }
}

extension WidgetSnapshot {
    /// Sample data for the widget gallery preview.
    static var preview: WidgetSnapshot {
        var s = WidgetSnapshot.empty
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for d in 0..<40 {
            let day = cal.date(byAdding: .day, value: -d, to: today)!
            let v: [TimeInterval] = [0, 2.5, 4, 6.2, 5, 0, 3, 7, 1.5]
            s.dailyTotals[dayKey(day)] = v[d % v.count] * 3600
        }
        s.todayWork = 3.4 * 3600
        s.phase = .working
        s.title = "RAID setup"
        s.path = "Server Storage › Disk setup › RAID setup"
        s.colorHex = "#C9A45C"
        s.sessionWork = 47 * 60
        s.blockLabel = "2 · 60/10"
        s.planName = "Daily flow"
        s.breaksEnabled = true
        s.workUntilBreak = 13 * 60
        return s
    }
}

// MARK: - Shared

enum WidgetPalette {
    // Athlos icon colors (same as the app's Theme).
    static let gold = Color(red: 0.831, green: 0.686, blue: 0.416)      // #D4AF6A
    static let goldDeep = Color(red: 0.663, green: 0.498, blue: 0.235)  // #A97F3C
    static let rest = Color(red: 0.42, green: 0.60, blue: 0.54)         // sage, breaks

    static func color(for seconds: TimeInterval, goal: TimeInterval) -> Color {
        guard seconds >= 60 else { return Color.secondary.opacity(0.18) }
        let ratio = seconds / max(goal, 1)
        if ratio >= 1 { return goldDeep }
        return gold.opacity(0.28 + 0.6 * min(ratio, 1))
    }

    static func hex(_ hex: String?) -> Color {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return gold }
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        return Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Formatting for the widgets. Widgets follow the system language (English or Turkish).
enum WFmt {
    static var isTurkish: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("tr") == true }

    static var locale: Locale {
        Locale(identifier: "\(isTurkish ? "tr" : "en")_\(Locale.current.region?.identifier ?? (isTurkish ? "TR" : "US"))")
    }

    static func hm(_ seconds: TimeInterval) -> String {
        let h1 = isTurkish ? "sa" : "h", m1 = isTurkish ? "dk" : "m"
        let m = max(0, Int(seconds / 60))
        let h = m / 60, mm = m % 60
        if h == 0 { return "\(mm)\(m1)" }
        if mm == 0 { return "\(h)\(h1)" }
        return "\(h)\(h1) \(mm)\(m1)"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    static var calendar: Calendar {
        var c = Calendar.current
        c.locale = locale
        c.firstWeekday = 2
        return c
    }
}

/// Hint shown when the app hasn't written any data yet.
struct NoDataHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "timer").font(.title2)
            Text("Open Athlos once to see your data.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}
