import WidgetKit
import SwiftUI
import AthlosCore

/// Monthly work heatmap widget.
struct HeatmapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.heatmapKind, provider: SnapshotProvider()) { entry in
            HeatmapWidgetView(entry: entry)
        }
        .configurationDisplayName("Work Calendar")
        .description("This month's work heatmap: how much you worked each day, with goal days in gold.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HeatmapWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: SnapshotEntry
    /// Lets the same view be rendered outside WidgetKit (README images); nil = use the real widget family.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var snap: WidgetSnapshot { entry.snapshot }
    private var cal: Calendar { WFmt.calendar }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            default: large
            }
        }
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
        .widgetURL(URL(string: "athlos://stats"))
    }

    // MARK: Sizes

    /// Small: month grid (no numbers) + today.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(monthTitle).font(.caption.weight(.semibold))
                Spacer()
                Text(WFmt.hm(snap.todayWork)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            MonthGrid(snapshot: snap, showNumbers: false, spacing: 2.5, corner: 3)
        }
    }

    /// Medium: month grid on the left, summary on the right.
    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(monthTitle).font(.caption.weight(.semibold))
                MonthGrid(snapshot: snap, showNumbers: true, spacing: 2.5, corner: 3, numberSize: 7)
            }
            .frame(maxWidth: 170)
            VStack(alignment: .leading, spacing: 8) {
                stat("Today", WFmt.hm(snap.todayWork), color: WidgetPalette.gold)
                stat("This month", WFmt.hm(monthTotal), color: WidgetPalette.goldDeep)
                stat("Goal days", "\(goalDays)", color: WidgetPalette.gold)
                Spacer(minLength: 0)
                goalBar
            }
        }
    }

    /// Large: title, weekday names, numbered month grid, summary and legend.
    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle).font(.headline)
                Spacer()
                Text("This month \(WFmt.hm(monthTotal))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            MonthGrid(snapshot: snap, showNumbers: true, spacing: 5, corner: 6, numberSize: 11, showDurations: true, showWeekdays: true)
            goalBar
            HStack(spacing: 4) {
                Text("Goal days: \(goalDays)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.25, 0.5, 0.8, 1.0], id: \.self) { f in
                    RoundedRectangle(cornerRadius: 2).fill(WidgetPalette.color(for: f * max(snap.goalSeconds, 1), goal: snap.goalSeconds))
                        .frame(width: 9, height: 9)
                }
                Text("Goal").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Parts

    private var goalBar: some View {
        let p = snap.todayWork / max(snap.goalSeconds, 1)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Daily goal").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(WFmt.hm(snap.todayWork)) / \(WFmt.hm(snap.goalSeconds))").font(.caption2.monospacedDigit())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(p >= 1 ? AnyShapeStyle(WidgetPalette.gold) : AnyShapeStyle(WidgetPalette.gold.opacity(0.85)))
                        .frame(width: max(p > 0 ? 4 : 0, g.size.width * min(p, 1)))
                }
            }
            .frame(height: 6)
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private var monthTitle: String {
        Date().formatted(.dateTime.month(.wide).year().locale(WFmt.locale)).capitalized(with: WFmt.locale)
    }

    private var monthInterval: DateInterval { cal.dateInterval(of: .month, for: Date())! }

    private var monthTotal: TimeInterval {
        var t: TimeInterval = 0
        var d = monthInterval.start
        while d < monthInterval.end {
            t += snap.seconds(on: d, calendar: cal)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return t
    }

    private var goalDays: Int {
        var n = 0
        var d = monthInterval.start
        while d < monthInterval.end {
            if snap.goalSeconds > 0, snap.seconds(on: d, calendar: cal) >= snap.goalSeconds { n += 1 }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return n
    }
}

/// This month's day grid, starting on Monday.
struct MonthGrid: View {
    let snapshot: WidgetSnapshot
    var showNumbers: Bool
    var spacing: CGFloat
    var corner: CGFloat
    var numberSize: CGFloat = 9
    var showDurations = false
    var showWeekdays = false

    var body: some View {
        let cal = WFmt.calendar
        let today = cal.startOfDay(for: Date())
        let month = cal.dateInterval(of: .month, for: today)!
        let count = cal.range(of: .day, in: .month, for: today)!.count
        let leading = (cal.component(.weekday, from: month.start) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: leading)
            + (0..<count).map { cal.date(byAdding: .day, value: $0, to: month.start)! }
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }

        VStack(spacing: spacing) {
            if showWeekdays {
                HStack(spacing: spacing) {
                    ForEach(weekdays(cal), id: \.self) { w in
                        Text(w).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
            }
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { c in
                        let day = c < rows[r].count ? rows[r][c] : nil
                        cell(day, today: today, cal: cal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: Date?, today: Date, cal: Calendar) -> some View {
        if let day {
            let secs = snapshot.seconds(on: day, calendar: cal)
            let future = day > today
            let isToday = day == today
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(future ? Color.secondary.opacity(0.07) : WidgetPalette.color(for: secs, goal: snapshot.goalSeconds))
                .overlay {
                    if showNumbers {
                        VStack(spacing: 0) {
                            Text("\(cal.component(.day, from: day))")
                                .font(.system(size: numberSize, weight: isToday ? .bold : .medium))
                            if showDurations, secs >= 60 {
                                Text(WFmt.hm(secs)).font(.system(size: 7)).opacity(0.85)
                            }
                        }
                        .foregroundStyle(secs / max(snapshot.goalSeconds, 1) > 0.45 ? Color.black.opacity(0.75) : Color.primary.opacity(future ? 0.3 : 0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    }
                }
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Color.primary, lineWidth: 1.5)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
        }
    }

    private func weekdays(_ cal: Calendar) -> [String] {
        let s = cal.shortWeekdaySymbols
        let f = cal.firstWeekday - 1
        return Array(s[f...] + s[..<f])
    }
}
