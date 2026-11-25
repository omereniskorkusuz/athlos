import SwiftUI
import AthlosCore

/// Menu bar popover: active topic, controls, daily goal bar, recent topics.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let phase = model.timer.phase
        VStack(alignment: .leading, spacing: 12) {
            // Title + time
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let p = model.activeProject {
                        ProjectIconView(project: p, size: 18, images: model.store.images)
                    }
                    Text(phase == .idle ? String(localized: "Timer ready") : model.activePath.joined(separator: " › "))
                        .font(.headline)
                        .lineLimit(2)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.clock(model.displaySeconds))
                        .font(.system(size: 34, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    Text(phaseText).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }

            // Controls
            HStack(spacing: 8) {
                switch phase {
                case .idle:
                    Button { model.toggleOrPick(); open() } label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                case .working, .paused:
                    Button { model.toggleOrPick() } label: {
                        Label(phase == .working ? "Pause" : "Resume", systemImage: phase == .working ? "pause.fill" : "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { model.timer.startBreak(); model.now = Date() } label: { Label("Break", systemImage: "cup.and.saucer.fill") }
                    Button(role: .destructive) { model.requestStop(); if model.store.settings.askNoteOnStop { open() } } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                case .onBreak:
                    Button { model.timer.resume(); model.now = Date() } label: { Label("End break", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    Button("Skip") { model.timer.skipBreak(); model.now = Date() }
                    Button("+\(model.store.settings.snoozeMinutes) min") { model.timer.snoozeBreak(); model.now = Date() }
                        .help("Snooze break")
                }
            }
            .controlSize(.large)

            GoalBarView(compact: true)

            let recents = model.store.recentTargets(limit: 5)
            if !recents.isEmpty {
                Divider()
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(Array(recents.enumerated()), id: \.offset) { _, r in
                        RecentRow(projectID: r.projectID, topicID: r.topicID, compact: true)
                    }
                }
            }

            Divider()
            Toggle("Desktop widget", isOn: Binding(get: { model.desktopWidgetVisible },
                                                     set: { model.setDesktopWidget(visible: $0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.callout)
            HStack {
                Button("Open Athlos") { open() }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Settings")
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 330)
    }

    private var phaseText: LocalizedStringKey {
        switch model.timer.phase {
        case .idle: "READY"
        case .working: "WORKING"
        case .paused: "PAUSED"
        case .onBreak: "BREAK"
        }
    }

    /// Opens the main window and closes the popover.
    private func open() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        dismiss()
    }
}
