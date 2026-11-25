import WidgetKit
import SwiftUI
import AppIntents
import AthlosCore

/// Live timer + start/pause/stop/break buttons.
struct TimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.timerKind, provider: SnapshotProvider()) { entry in
            TimerWidgetView(entry: entry)
        }
        .configurationDisplayName("Athlos Timer")
        .description("See your work time live; start, pause, take a break and stop.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TimerWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: SnapshotEntry
    /// Lets the same view be rendered outside WidgetKit (README images); nil = use the real widget family.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var snap: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            header
            time
            if family == .systemMedium {
                info
            }
            Spacer(minLength: 0)
            controls
        }
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 5) {
            Circle().fill(WidgetPalette.hex(snap.colorHex)).frame(width: 7, height: 7)
                .opacity(snap.phase == .idle ? 0 : 1)
            Text(snap.phase == .idle ? "Athlos" : (snap.title ?? "Athlos"))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(phaseText)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(phaseColor)
        }
    }

    @ViewBuilder
    private var time: some View {
        let size: CGFloat = family == .systemSmall ? 30 : 38
        Group {
            switch snap.phase {
            case .working:
                // The widget runs the clock itself; the app doesn't need to reload it every second.
                Text(snap.sessionTimerStart, style: .timer)
            case .onBreak:
                if let end = snap.breakEndsAt, end > entry.date {
                    Text(timerInterval: entry.date...end, countsDown: true)
                } else {
                    Text("00:00")
                }
            case .paused:
                Text(WFmt.clock(snap.sessionWork))
            case .idle:
                Text("00:00:00")
            }
        }
        .font(.system(size: size, weight: .light, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(snap.phase == .paused ? .secondary : .primary)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let path = snap.path, snap.phase != .idle {
                Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                Label {
                    if snap.phase == .working {
                        Text(snap.todayTimerStart, style: .timer).monospacedDigit()
                    } else {
                        Text(WFmt.hm(snap.todayWork))
                    }
                } icon: { Image(systemName: "sun.max") }
                if snap.breaksEnabled, let left = snap.workUntilBreak, snap.phase == .working || snap.phase == .paused {
                    Label("break in \(WFmt.hm(left + 59))", systemImage: "hourglass")
                }
                if let block = snap.blockLabel { Text("Block \(block)") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 6) {
            switch snap.phase {
            case .idle:
                Button(intent: ToggleTimerIntent()) {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .tint(.accentColor)
            case .working:
                Button(intent: ToggleTimerIntent()) {
                    Label(family == .systemSmall ? "" : "Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                }
                .tint(.accentColor)
                Button(intent: StartBreakIntent()) { Image(systemName: "cup.and.saucer.fill") }
                Button(intent: StopTimerIntent()) { Image(systemName: "stop.fill") }
            case .paused:
                Button(intent: ToggleTimerIntent()) {
                    Label(family == .systemSmall ? "" : "Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .tint(.accentColor)
                Button(intent: StartBreakIntent()) { Image(systemName: "cup.and.saucer.fill") }
                Button(intent: StopTimerIntent()) { Image(systemName: "stop.fill") }
            case .onBreak:
                Button(intent: ToggleTimerIntent()) {
                    Label(family == .systemSmall ? "" : "End break", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .tint(.accentColor)
                Button(intent: SkipBreakIntent()) { Image(systemName: "forward.fill") }
                Button(intent: StopTimerIntent()) { Image(systemName: "stop.fill") }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(family == .systemSmall ? .small : .regular)
        .labelStyle(.titleAndIcon)
    }

    private var phaseText: LocalizedStringKey {
        switch snap.phase {
        case .idle: "READY"
        case .working: "WORKING"
        case .paused: "PAUSED"
        case .onBreak: "BREAK"
        }
    }

    private var phaseColor: Color {
        switch snap.phase {
        case .idle: .secondary
        case .working: .green
        case .paused: .yellow
        case .onBreak: .orange
        }
    }
}

// MARK: - Buttons (App Intents)

/// Shared: pass the command to the app and wait briefly until the app updates the snapshot.
private func relay(_ command: WidgetCommand) async {
    let before = WidgetSnapshot.load()?.generatedAt
    try? command.send()
    // After the app handles the command and writes a new snapshot, the widget reloads with the right state (~1.5 s at most).
    for _ in 0..<15 {
        try? await Task.sleep(for: .milliseconds(100))
        if let now = WidgetSnapshot.load()?.generatedAt, now != before { break }
    }
}

struct ToggleTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start / pause timer"
    static let isDiscoverable = false
    func perform() async throws -> some IntentResult {
        await relay(.toggle)
        return .result()
    }
}

struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop session"
    static let isDiscoverable = false
    func perform() async throws -> some IntentResult {
        await relay(.stop)
        return .result()
    }
}

struct StartBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Start break"
    static let isDiscoverable = false
    func perform() async throws -> some IntentResult {
        await relay(.startBreak)
        return .result()
    }
}

struct SkipBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip break"
    static let isDiscoverable = false
    func perform() async throws -> some IntentResult {
        await relay(.skipBreak)
        return .result()
    }
}
