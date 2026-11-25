import SwiftUI
import Charts
import AthlosCore

/// Statistics: summary tiles, stacked chart per project, heatmap, ratio, tree table + history.
struct StatsView: View {
    enum Tab: String, CaseIterable { case summary, history }
    @State private var tab: Tab = DemoData.statsTab == "history" ? .history : .summary

    var body: some View {
        Group {
            switch tab {
            case .summary: StatsSummaryView()
            case .history: HistoryView()
            }
        }
        .navigationTitle("Statistics")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    Text("Overview").tag(Tab.summary)
                    Text("History").tag(Tab.history)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }
}

// MARK: - Overview

enum ChartRange: String, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        }
    }

    var count: Int {
        switch self {
        case .daily: 14
        case .weekly: 12
        case .monthly: 12
        }
    }
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let bucket: Date
    let project: String
    let hours: Double
}

struct StatsSummaryView: View {
    @Environment(AppModel.self) private var model
    @State private var range: ChartRange = .daily

    private var calendar: Calendar {
        var c = Calendar.current
        c.locale = Fmt.locale
        c.firstWeekday = 2 // Monday
        return c
    }

    var body: some View {
        let now = model.now
        let store = model.store
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Summary tiles
                let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)!
                let weekWork = Stats.seconds(store.entries, kind: .work, in: weekInterval, now: now)
                let streak = store.currentStreak(now: now, calendar: calendar)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    StatTile(title: "Today", value: Fmt.hm(model.todayWork), systemImage: "sun.max", tint: Theme.brand)
                    StatTile(title: "This week", value: Fmt.hm(weekWork), systemImage: "calendar", tint: Theme.brandDeep)
                    StatTile(title: "Streak", value: String(localized: "\(streak) days"), systemImage: "flame.fill", tint: Theme.brandBright)
                    StatTile(title: "Breaks today", value: Fmt.hm(store.todayBreakSeconds(now: now)), systemImage: "cup.and.saucer", tint: Theme.rest)
                }

                // Stacked chart per project
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Work time").font(Theme.heading)
                        Spacer()
                        Picker("Range", selection: $range) {
                            ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    let (points, domain, colors) = chartData(now: now)
                    if points.isEmpty {
                        Text("No entries in this range.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        Chart(points) { p in
                            BarMark(x: .value("Period", p.bucket, unit: range.component, calendar: calendar),
                                    y: .value("Time", p.hours))
                                .foregroundStyle(by: .value("Project", p.project))
                                .cornerRadius(3)
                        }
                        .chartForegroundStyleScale(domain: domain, range: colors)
                        .chartYAxisLabel("hours")
                        .chartXAxis {
                            AxisMarks(values: .stride(by: range.component, count: range == .daily ? 2 : 1)) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: range == .monthly ? .dateTime.month(.abbreviated).locale(Fmt.locale)
                                               : .dateTime.day().month(.abbreviated).locale(Fmt.locale), centered: true)
                            }
                        }
                        .frame(height: 260)
                        .animation(.smooth, value: range)
                    }
                }
                .card()

                HStack(alignment: .top, spacing: 16) {
                    // Heatmap
                    // Monthly calendar (heatmap)
                    MonthHeatmapView()
                        .card()
                    // Work / break ratio
                    RatioView(range: range, now: now, calendar: calendar)
                        .card()
                        .frame(width: 260)
                }

                ProjectTotalsTable(now: now)
                    .card()
            }
            .padding(24)
        }
        .defaultScrollAnchor(DemoData.statsTab == "calendar" ? UnitPoint(x: 0.5, y: 0.62) : .top)
    }

    /// Bars (period × project) for the selected range.
    private func chartData(now: Date) -> ([ChartPoint], [String], [Color]) {
        let store = model.store
        let cal = calendar
        let currentBucket = cal.dateInterval(of: range.component, for: now)!.start
        let firstBucket = cal.date(byAdding: range.component, value: -(range.count - 1), to: currentBucket)!
        let end = cal.dateInterval(of: range.component, for: now)!.end

        var points: [ChartPoint] = []
        var domain: [String] = []
        var colors: [Color] = []
        for p in store.projects.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let entries = store.entries.filter { $0.projectID == p.id }
            guard !entries.isEmpty else { continue }
            let daily = Stats.dailyTotals(entries, from: firstBucket, to: end, now: now, calendar: cal)
            var buckets: [Date: TimeInterval] = [:]
            for (day, secs) in daily {
                let b = cal.dateInterval(of: range.component, for: day)!.start
                buckets[b, default: 0] += secs
            }
            let nonZero = buckets.filter { $0.value > 0 }
            guard !nonZero.isEmpty else { continue }
            // Keep projects with the same name apart in the chart.
            let label = domain.contains(p.name) ? "\(p.name) (\(domain.count + 1))" : p.name
            domain.append(label)
            colors.append(p.color)
            for (b, secs) in nonZero { points.append(ChartPoint(bucket: b, project: label, hours: secs / 3600)) }
        }
        return (points, domain, colors)
    }
}

// MARK: - Work / break ratio

struct RatioView: View {
    @Environment(AppModel.self) private var model
    let range: ChartRange
    let now: Date
    let calendar: Calendar

    var body: some View {
        let current = calendar.dateInterval(of: range.component, for: now)!
        let start = calendar.date(byAdding: range.component, value: -(range.count - 1), to: current.start)!
        let interval = DateInterval(start: start, end: current.end)
        let work = Stats.seconds(model.store.entries, kind: .work, in: interval, now: now)
        let rest = Stats.seconds(model.store.entries, kind: .breakTime, in: interval, now: now)
        let total = max(work + rest, 1)

        VStack(alignment: .leading, spacing: 10) {
            Text("Work / break").font(Theme.heading)
            Chart {
                SectorMark(angle: .value("Work", work), innerRadius: .ratio(0.62), angularInset: 2)
                    .foregroundStyle(Theme.brand).cornerRadius(4)
                SectorMark(angle: .value("Break", max(rest, work == 0 ? 1 : 0)), innerRadius: .ratio(0.62), angularInset: 2)
                    .foregroundStyle(Theme.rest).cornerRadius(4)
            }
            .chartBackground { _ in
                VStack {
                    Text(verbatim: (work / total).formatted(.percent.precision(.fractionLength(0)).locale(Fmt.numberLocale))).font(Theme.display(22))
                    Text("work").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 150)
            Label("Work: \(Fmt.hm(work))", systemImage: "circle.fill").foregroundStyle(Theme.brandText).font(.callout)
            Label("Break: \(Fmt.hm(rest))", systemImage: "circle.fill").foregroundStyle(Theme.rest).font(.callout)
            Text(range == .daily ? "Range: last 14 days" : range == .weekly ? "Range: last 12 weeks" : "Range: last 12 months")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Project / topic totals (tree)

struct ProjectTotalsTable: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let store = model.store
        let today = Stats.dayInterval(now)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Project and topic totals").font(Theme.heading)
                Spacer()
                Text("Today").frame(width: 80, alignment: .trailing)
                Text("Total").frame(width: 90, alignment: .trailing)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(store.projects.sorted { ($0.status == .completed ? 1 : 0, $0.sortIndex) < ($1.status == .completed ? 1 : 0, $1.sortIndex) }) { p in
                let totals = store.rolledUpTotals(projectID: p.id, now: now)
                let todays = store.rolledUpTotals(projectID: p.id, in: today, now: now)
                DisclosureGroup {
                    TotalsRows(projectID: p.id, parentID: nil, totals: totals, todays: todays, depth: 0)
                } label: {
                    HStack {
                        ProjectIconView(project: p, size: 20, images: store.images)
                        Text(p.name).fontWeight(.semibold)
                        if p.status == .completed { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.goalColor).font(.caption) }
                        Spacer()
                        Text(Fmt.hm(store.projectSeconds(p.id, in: today, now: now))).frame(width: 80, alignment: .trailing)
                        Text(Fmt.hm(store.projectSeconds(p.id, now: now))).fontWeight(.semibold).frame(width: 90, alignment: .trailing)
                    }
                    .monospacedDigit()
                }
                Divider()
            }
        }
    }
}

private struct TotalsRows: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    let parentID: UUID?
    let totals: [UUID: TimeInterval]
    let todays: [UUID: TimeInterval]
    let depth: Int

    var body: some View {
        ForEach(model.store.children(projectID: projectID, parentID: parentID)) { t in
            HStack {
                Text(t.name).padding(.leading, CGFloat(depth) * 16)
                Spacer()
                Text(Fmt.hm(todays[t.id] ?? 0)).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                Text(Fmt.hm(totals[t.id] ?? 0)).frame(width: 90, alignment: .trailing)
            }
            .monospacedDigit()
            .font(.callout)
            TotalsRows(projectID: projectID, parentID: t.id, totals: totals, todays: todays, depth: depth + 1)
        }
    }
}

extension View {
    /// Statistics card style.
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .athlosCard(radius: 14)
    }
}
