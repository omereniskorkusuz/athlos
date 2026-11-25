import SwiftUI
import AthlosCore

/// Right-hand "Today" panel on the Timer screen: total vs goal, a bar of work per project,
/// a day timeline (work blocks, breaks, now), the day's sessions and today's notes.
struct TodayPanel: View {
    @Environment(AppModel.self) private var model
    static let width: CGFloat = 260

    var body: some View {
        let now = model.now
        let day = Stats.dayInterval(now)
        let summary = DaySummary.make(model.store.entries, day: day, now: now)
        let goal = max(model.dailyGoal, 1)
        let work = model.todayWork
        let progress = work / goal

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Today")
                    Spacer()
                    Text(verbatim: String(localized: "\(progress.formatted(.percent.precision(.fractionLength(0)).locale(Fmt.numberLocale))) of goal"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(progress >= 1 ? Theme.brandDeep : Theme.brandText)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.hm(work)).font(Theme.display(30, weight: .bold)).foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text(verbatim: "/ " + Fmt.hm(goal)).font(.system(size: 14)).foregroundStyle(Theme.inkSecondary)
                }
                .monospacedDigit()

                ProjectBar(summary: summary, goal: goal)
                DayTimeline(summary: summary, day: day, now: now)
                sessions(summary)
                notes(day: day)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.never)
        .frame(width: TodayPanel.width)
        .background {
            // Runs up under the title bar like the rail.
            HStack(spacing: 0) { Theme.line.frame(width: 1); Theme.panel }
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: Sessions

    @ViewBuilder
    private func sessions(_ s: DaySummary) -> some View {
        VStack(spacing: 0) {
            if s.rows.isEmpty {
                Text("Nothing recorded yet today.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            ForEach(s.rows.prefix(8)) { r in
                SessionRow(row: r)
            }
            if s.breakCount > 0 {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.rest).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Breaks").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                        Text("\(s.breakCount) breaks").font(.system(size: 11.5)).foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    Text(Fmt.hm(s.breakSeconds)).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    // MARK: Notes

    @ViewBuilder
    private func notes(day: DateInterval) -> some View {
        let todays = model.store.notes.filter { day.contains($0.createdAt) }.sorted { $0.createdAt > $1.createdAt }
        if !todays.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's notes").font(.system(size: 12)).foregroundStyle(Theme.inkSecondary)
                ForEach(todays.prefix(5)) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Fmt.time(n.createdAt)).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                        Text(n.text).font(.system(size: 13)).foregroundStyle(Theme.ink).lineLimit(3).textSelection(.enabled)
                    }
                }
            }
        }
    }
}

/// One session in the Today list: project color, topic, time range, duration. Click to continue it.
private struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let row: DaySummary.Row
    @State private var hovering = false

    var body: some View {
        let store = model.store
        let project = store.project(row.projectID)
        let title = row.topicID.flatMap { store.topic($0)?.name } ?? project?.name ?? "—"
        let running = row.end == nil
        Button {
            if !running { model.start(projectID: row.projectID, topicID: row.topicID) }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(project?.color ?? Theme.inkTertiary).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    // Times first so they never get cut off; the project name truncates instead.
                    Text(verbatim: "\(Fmt.time(row.start)) – \(row.end.map(Fmt.time) ?? String(localized: "now")) · \(project?.name ?? "")")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(Fmt.hm(row.seconds))
                    .font(.system(size: 12.5, weight: running ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(running ? Theme.brandText : Theme.inkSecondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, hovering ? 6 : 0)
            .background(hovering ? Theme.ink.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = running ? false : $0 }
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .help(running ? Text("Running now") : Text("Continue this topic"))
        .animation(.smooth(duration: 0.15), value: hovering)
    }
}

/// Work per project as one bar that fills toward the daily goal.
private struct ProjectBar: View {
    @Environment(AppModel.self) private var model
    let summary: DaySummary
    let goal: TimeInterval

    var body: some View {
        let total = max(goal, summary.workSeconds, 1)
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(summary.projects, id: \.id) { p in
                        Rectangle()
                            .fill(model.store.project(p.id)?.color ?? Theme.inkTertiary)
                            .frame(width: max(2, (geo.size.width - CGFloat(summary.projects.count) * 2) * p.seconds / total))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.track)
                .clipShape(Capsule())
            }
            .frame(height: 10)
            // Legend: up to three projects.
            FlowLegend(items: summary.projects.prefix(3).map { p in
                (model.store.project(p.id)?.color ?? Theme.inkTertiary, model.store.project(p.id)?.name ?? "—", Fmt.hm(p.seconds))
            })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Work by project")
        .accessibilityValue(Text(summary.projects.map { "\(model.store.project($0.id)?.name ?? ""): \(Fmt.spoken($0.seconds))" }.joined(separator: ", ")))
    }
}

private struct FlowLegend: View {
    let items: [(Color, String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(item.0).frame(width: 8, height: 8)
                    Text(item.1).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.2).monospacedDigit()
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

/// The day from (at least) 08:00 to 18:00: work blocks in project colors, breaks in steel blue, a line at now.
private struct DayTimeline: View {
    @Environment(AppModel.self) private var model
    let summary: DaySummary
    let day: DateInterval
    let now: Date

    var body: some View {
        let cal = Calendar.current
        let firstHour = summary.segments.first.map { cal.component(.hour, from: $0.start) } ?? 8
        let lastEnd = max(summary.segments.map(\.end).max() ?? now, now)
        let lastHour = cal.component(.hour, from: lastEnd) + 1
        let startHour = min(8, firstHour)
        let rawEnd = min(24, max(18, lastHour))
        let step = (rawEnd - startHour) > 12 ? 4 : 2
        // Round the end up so the hour labels are evenly spaced.
        let endHour = startHour + Int((Double(rawEnd - startHour) / Double(step)).rounded(.up)) * step
        let span = Double(endHour - startHour) * 3600
        let origin = day.start.addingTimeInterval(Double(startHour) * 3600)
        let labels = Array(stride(from: startHour, through: endHour, by: step))

        VStack(spacing: 5) {
            GeometryReader { geo in
                let w = geo.size.width
                let x: (Date) -> CGFloat = { CGFloat($0.timeIntervalSince(origin) / span) * w }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(Theme.track)
                    ForEach(Array(summary.segments.enumerated()), id: \.offset) { _, seg in
                        let isBreak = seg.kind == .breakTime
                        RoundedRectangle(cornerRadius: isBreak ? 2 : 4)
                            .fill(isBreak ? Theme.rest : (model.store.project(seg.projectID)?.color ?? Theme.brand))
                            .frame(width: max(2, x(seg.end) - x(seg.start)), height: isBreak ? 10 : 18)
                            .offset(x: x(seg.start))
                    }
                    if day.contains(now) {
                        RoundedRectangle(cornerRadius: 1).fill(Theme.ink)
                            .frame(width: 2, height: 24)
                            .offset(x: min(max(0, x(now) - 1), w - 2))
                    }
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            HStack {
                ForEach(labels, id: \.self) { h in
                    Text(verbatim: String(format: "%02d", h))
                    if h != labels.last { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 10.5))
            .monospacedDigit()
            .foregroundStyle(Theme.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day timeline")
    }
}
