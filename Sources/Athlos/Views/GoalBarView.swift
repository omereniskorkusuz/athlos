import SwiftUI
import AthlosCore

/// Daily goal bar: fills second by second with work time; breaks don't count.
/// Past the goal it turns deep copper and the overflow is shown separately.
struct GoalBarView: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        let work = model.todayWork
        let goal = max(model.dailyGoal, 1)
        let progress = work / goal
        let reached = progress >= 1

        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(alignment: .firstTextBaseline) {
                if !compact {
                    Label("Daily goal", systemImage: reached ? "checkmark.seal.fill" : "target")
                        .font(.headline)
                        .foregroundStyle(reached ? Theme.brandText : Theme.ink)
                }
                Text("\(Fmt.hm(work)) / \(Fmt.hm(goal))")
                    .font(compact ? .caption.weight(.medium) : .headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Spacer()
                Text(verbatim: progress.formatted(.percent.precision(.fractionLength(0)).locale(Fmt.numberLocale)))
                    .font(compact ? .caption2 : .subheadline)
                    .monospacedDigit()
                    .foregroundStyle(reached ? Theme.brandText : Theme.inkSecondary)
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    if reached {
                        // Goal reached: the full bar is deep copper; the overflow is a bright stripe.
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.brandDeep, Theme.brandBright], startPoint: .leading, endPoint: .trailing))
                            .frame(width: w)
                            .shadow(color: Theme.brandBright.opacity(0.6), radius: 4)
                        let overflow = min(progress - 1, 1)
                        if overflow > 0 {
                            Capsule()
                                .fill(.white.opacity(0.35))
                                .frame(width: max(4, w * overflow))
                        }
                    } else {
                        Capsule()
                            .fill(Theme.brandGradient)
                            .frame(width: max(progress > 0 ? 6 : 0, w * progress))
                    }
                }
            }
            .frame(height: compact ? 6 : 14)

            if !compact, reached, progress > 1 {
                Text("\(Fmt.hm(work - goal)) over your goal")
                    .font(.caption)
                    .foregroundStyle(Theme.brandText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily goal")
        .accessibilityValue(Text("\(Fmt.spoken(work)) / \(Fmt.spoken(goal))"))
    }
}
