import SwiftUI
import AthlosCore

/// Desktop widget content: live timer, start/pause/stop/break, daily goal bar, (large) monthly calendar.
struct DesktopWidgetView: View {
    @Environment(AppModel.self) private var model
    let size: DesktopWidgetSize

    var body: some View {
        let phase = model.timer.phase
        VStack(alignment: .leading, spacing: 10) {
            // Header row (drag handle)
            HStack(spacing: 6) {
                if let p = model.activeProject {
                    ProjectIconView(project: p, size: 18, images: model.store.images)
                } else {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 18, height: 18)
                }
                Text(phase == .idle ? String(localized: "Athlos") : (model.activePath.last ?? ""))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(phaseText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phaseColor)
            }
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())

            // Time
            Text(Fmt.clock(model.displaySeconds))
                .font(.system(size: size == .small ? 38 : 46, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: phase == .onBreak))
                .foregroundStyle(phase == .paused ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .gesture(WindowDragGesture())

            if size != .small, phase != .idle, model.activePath.count > 1 {
                Text(model.activePath.dropLast().joined(separator: " › "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            controls(phase)

            if size != .small {
                GoalBarView(compact: true)
                if model.store.settings.breaksEnabled, let left = model.timer.workUntilBreak(now: model.now) {
                    Label("Break in \(Fmt.hm(left + 59)) · Block \(model.timer.currentBlockNumber)", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if size == .large {
                Divider()
                MonthHeatmapView(compact: true)
            }
        }
        .padding(14)
        .frame(width: size.width)
        .fixedSize(horizontal: false, vertical: true)
        .athlosCard(radius: 22)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .contextMenu { menu }
    }

    // MARK: Parts

    @ViewBuilder
    private func controls(_ phase: TimerPhase) -> some View {
        HStack(spacing: 8) {
            switch phase {
            case .idle:
                button("Start", "play.fill", prominent: true) { model.toggleOrPick(fromHotKey: true) }
            case .working:
                button("Pause", "pause.fill", prominent: true) { model.toggleOrPick() }
                iconButton("cup.and.saucer.fill", help: "Break") { model.timer.startBreak(); model.now = Date() }
                iconButton("stop.fill", help: "Stop") { model.requestStop() }
            case .paused:
                button("Resume", "play.fill", prominent: true) { model.toggleOrPick() }
                iconButton("cup.and.saucer.fill", help: "Break") { model.timer.startBreak(); model.now = Date() }
                iconButton("stop.fill", help: "Stop") { model.requestStop() }
            case .onBreak:
                button("End break", "play.fill", prominent: true) { model.timer.resume(); model.now = Date() }
                iconButton("forward.fill", help: "Skip break") { model.timer.skipBreak(); model.now = Date() }
                iconButton("stop.fill", help: "Stop") { model.requestStop() }
            }
        }
        .controlSize(size == .small ? .regular : .large)
    }

    private func button(_ title: LocalizedStringKey, _ symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22)
        }
        .buttonStyle(.bordered)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    @ViewBuilder
    private var menu: some View {
        Picker("Size", selection: Binding(get: { size }, set: { model.desktopWidgetSize = $0 })) {
            ForEach(DesktopWidgetSize.allCases) { Text($0.title).tag($0) }
        }
        Divider()
        Button("Choose topic…") { model.route = .timer; model.openQuickPicker(switchOnly: model.timer.phase != .idle); model.bringToFront() }
        Button("Open Athlos") { model.bringToFront() }
        Divider()
        Button("Hide widget") { model.setDesktopWidget(visible: false) }
    }

    private var phaseText: LocalizedStringKey {
        switch model.timer.phase {
        case .idle: "READY"
        case .working: "WORKING"
        case .paused: "PAUSED"
        case .onBreak: "BREAK"
        }
    }

    private var phaseColor: Color {
        switch model.timer.phase {
        case .idle: .secondary
        case .working: Theme.brand
        case .paused: Theme.paused
        case .onBreak: Theme.rest
        }
    }
}
