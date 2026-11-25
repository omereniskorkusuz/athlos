import SwiftUI
import AthlosCore

/// Monthly work calendar (heatmap). One box per day; the color fills with that day's work,
/// goal days in gold. No scroll view → boxes aren't cut off and clicks land exactly.
struct MonthHeatmapView: View {
    @Environment(AppModel.self) private var model
    /// Smaller, simpler drawing for the widget (no day numbers).
    var compact = false

    @State private var month: Date = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var hovered: Date?
    @State private var selected: Date?

    private var calendar: Calendar {
        var c = Calendar.current
        c.locale = Fmt.locale
        c.firstWeekday = 2 // Monday
        return c
    }

    var body: some View {
        let cal = calendar
        let now = model.now
        let monthInterval = cal.dateInterval(of: .month, for: month)!
        let totals = Stats.dailyTotals(model.store.entries, from: monthInterval.start, to: monthInterval.end, now: now, calendar: cal)
        let goal = model.store.settings.dailyGoalSeconds
        let days = daysInMonth(cal)
        let leading = (cal.component(.weekday, from: monthInterval.start) - cal.firstWeekday + 7) % 7
        let cellSpacing: CGFloat = compact ? 4 : 6

        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            header(cal: cal, totals: totals, goal: goal)

            // Weekday names
            HStack(spacing: cellSpacing) {
                ForEach(weekdaySymbols(cal), id: \.self) { s in
                    Text(s)
                        .font(compact ? .system(size: 9, weight: .medium) : .caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7), spacing: cellSpacing) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                ForEach(days, id: \.self) { day in
                    dayCell(day, seconds: totals[day] ?? 0, goal: goal, today: cal.startOfDay(for: now), cal: cal)
                }
            }

            footer(totals: totals, goal: goal)
        }
        .frame(maxWidth: compact ? .infinity : 460, alignment: .leading) // keep the boxes from growing too big
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Monthly work calendar")
    }

    // MARK: Parts

    private func header(cal: Calendar, totals: [Date: TimeInterval], goal: TimeInterval) -> some View {
        let isCurrent = cal.isDate(month, equalTo: Date(), toGranularity: .month)
        return HStack(spacing: 6) {
            Text(month.formatted(.dateTime.month(.wide).year().locale(Fmt.locale)).capitalized(with: Fmt.locale))
                .font(compact ? .subheadline.weight(.semibold) : .title3.bold())
            Spacer()
            if !isCurrent {
                Button("Today") { withAnimation { month = cal.dateInterval(of: .month, for: Date())!.start } }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Button { shift(-1, cal) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous month")
            Button { shift(1, cal) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(isCurrent)
                .accessibilityLabel("Next month")
        }
    }

    private func dayCell(_ day: Date, seconds: TimeInterval, goal: TimeInterval, today: Date, cal: Calendar) -> some View {
        let isFuture = day > today
        let isToday = cal.isDate(day, inSameDayAs: today)
        let isFocused = hovered == day || selected == day
        return Button {
            selected = (selected == day) ? nil : day
        } label: {
            RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous)
                .fill(isFuture ? Color.secondary.opacity(0.06) : Self.color(for: seconds, goal: goal))
                .overlay {
                    // Only the day number in the widget; the large view also shows the time.
                    VStack(spacing: 0) {
                        Text("\(cal.component(.day, from: day))")
                            .font(compact ? .system(size: 10, weight: isToday ? .bold : .medium) : .caption.weight(isToday ? .bold : .medium))
                        if !compact, seconds >= 60 {
                                Text(Fmt.hm(seconds)).font(.system(size: 9)).opacity(0.85)
                        }
                    }
                    .foregroundStyle(seconds / max(goal, 1) > 0.45 ? Color.black.opacity(0.75) : Color.primary.opacity(isFuture ? 0.3 : 0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous)
                        .strokeBorder(isToday ? Color.accentColor : Color.primary.opacity(isFocused ? 0.7 : 0),
                                      lineWidth: isToday ? 2 : 1.5)
                }
                .aspectRatio(1, contentMode: .fit)
                .contentShape(Rectangle()) // the click area is the whole box
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .onHover { inside in
            if inside { hovered = day } else if hovered == day { hovered = nil }
        }
        .help("\(Fmt.weekdayDate(day)): \(Fmt.hm(seconds))")
        .accessibilityLabel(Text("\(Fmt.weekdayDate(day)), \(Fmt.spoken(seconds))"))
    }

    private func footer(totals: [Date: TimeInterval], goal: TimeInterval) -> some View {
        let monthTotal = totals.values.reduce(0, +)
        let goalDays = totals.values.filter { $0 >= goal && goal > 0 }.count
        let focus = hovered ?? selected
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let d = focus {
                    Text("\(Fmt.weekdayDate(d)) · \(Fmt.hm(totals[d] ?? 0))")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                } else {
                    Text("This month \(Fmt.hm(monthTotal)) · goal met on \(goalDays) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
                if !compact {
                    Text("Less").font(.caption2).foregroundStyle(.secondary)
                    ForEach([0.0, 0.2, 0.5, 0.8, 1.0], id: \.self) { f in
                        RoundedRectangle(cornerRadius: 2).fill(Self.color(for: f * max(goal, 1), goal: goal)).frame(width: 10, height: 10)
                    }
                    Text("Goal").font(.caption2).foregroundStyle(.secondary)
                }
            }
            // The selected day per project
            if !compact, let d = selected {
                DayBreakdown(day: d, calendar: calendar)
            }
        }
    }

    // MARK: Helpers

    /// 0 → gray; a little → light green (still visible); darker green toward the goal; goal → gold.
    static func color(for seconds: TimeInterval, goal: TimeInterval) -> Color {
        guard seconds >= 60 else { return Color.secondary.opacity(0.15) }
        let ratio = seconds / max(goal, 1)
        if ratio >= 1 { return .goalGold }
        return Color.green.opacity(0.35 + 0.6 * min(ratio, 1))
    }

    private func daysInMonth(_ cal: Calendar) -> [Date] {
        let range = cal.range(of: .day, in: .month, for: month)!
        let start = cal.dateInterval(of: .month, for: month)!.start
        return range.map { cal.date(byAdding: .day, value: $0 - 1, to: start)! }
    }

    private func weekdaySymbols(_ cal: Calendar) -> [String] {
        // "Mon Tue Wed …" (single letters are ambiguous in Turkish: P = Pazartesi/Perşembe/Pazar)
        let s = cal.shortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    private func shift(_ delta: Int, _ cal: Calendar) {
        selected = nil
        withAnimation(.smooth(duration: 0.2)) {
            month = cal.date(byAdding: .month, value: delta, to: month).map { cal.dateInterval(of: .month, for: $0)!.start } ?? month
        }
    }
}

/// Work on the selected day, per project.
private struct DayBreakdown: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let calendar: Calendar

    var body: some View {
        let interval = calendar.dateInterval(of: .day, for: day)!
        let rows = model.store.projects.map { p in (p, model.store.projectSeconds(p.id, in: interval, now: model.now)) }
            .filter { $0.1 >= 60 }
            .sorted { $0.1 > $1.1 }
        VStack(alignment: .leading, spacing: 4) {
            if rows.isEmpty {
                Text("No work recorded on this day.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0.id) { p, secs in
                HStack(spacing: 6) {
                    Circle().fill(p.color).frame(width: 7, height: 7)
                    Text(p.name).font(.caption)
                    Spacer()
                    Text(Fmt.hm(secs)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
