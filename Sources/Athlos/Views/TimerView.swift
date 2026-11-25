import SwiftUI
import AthlosCore

/// Main screen: big timer, active topic path, controls, break status, quick note and daily goal bar.
struct TimerView: View {
    @Environment(AppModel.self) private var model
    @State private var quickNote = ""
    @FocusState private var noteFocused: Bool
    @FocusState private var rootFocused: Bool
    @State private var showBlockAdjust = false

    var body: some View {
        if model.store.projects.isEmpty {
            WelcomeView()
        } else {
            content
        }
    }

    private var phase: TimerPhase { model.timer.phase }

    private var content: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 10)
                header
                clock
                controls
                breakInfo
                if phase != .idle { noteField }
                GoalBarView()
                    .padding(18)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if phase == .idle { recentList }
                sessionNotes
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Timer")
        // Space: start / pause (when a text field has focus, the field takes the space itself).
        .focusable()
        .focusEffectDisabled()
        .focused($rootFocused)
        .onKeyPress(.space) {
            guard !noteFocused else { return .ignored }
            model.toggleOrPick()
            return .handled
        }
        .onAppear { rootFocused = true }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 8) {
            Text(phaseTitle)
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(phaseColor)
                .contentTransition(.opacity)
            Button {
                model.openQuickPicker(switchOnly: phase != .idle)
            } label: {
                HStack(spacing: 6) {
                    if let p = model.activeProject {
                        ProjectIconView(project: p, size: 20, images: model.store.images)
                        ForEach(Array(model.activePath.enumerated()), id: \.offset) { i, part in
                            if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                            Text(part).fontWeight(i == model.activePath.count - 1 ? .semibold : .regular)
                        }
                    } else {
                        Image(systemName: "magnifyingglass")
                        Text("Choose topic")
                    }
                }
                .font(.title3)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Choose topic (⌘K)")
            .accessibilityLabel(Text("Active topic: \(model.activePath.joined(separator: ", "))"))
        }
    }

    private var clock: some View {
        Text(Fmt.clock(model.displaySeconds))
            .font(.system(size: 96, weight: .thin, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: phase == .onBreak))
            .animation(.smooth(duration: 0.3), value: Int(model.displaySeconds))
            .foregroundStyle(phase == .paused ? .secondary : .primary)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .accessibilityLabel(phase == .onBreak ? Text("\(Fmt.spoken(model.displaySeconds)) left in break") : Text("Elapsed \(Fmt.spoken(model.displaySeconds))"))
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 14) {
            switch phase {
            case .idle:
                bigButton("Start", symbol: "play.fill", prominent: true) { model.toggleOrPick() }
            case .working:
                bigButton("Pause", symbol: "pause.fill", prominent: true) { model.toggleOrPick() }
                bigButton("Break", symbol: "cup.and.saucer.fill") { model.timer.startBreak(); model.now = Date() }
                bigButton("Stop", symbol: "stop.fill", role: .destructive) { model.requestStop() }
            case .paused:
                bigButton(model.store.runtime.awaitingResumeAfterBreak ? "Let's continue" : "Resume", symbol: "play.fill", prominent: true) { model.toggleOrPick() }
                bigButton("Break", symbol: "cup.and.saucer.fill") { model.timer.startBreak(); model.now = Date() }
                bigButton("Stop", symbol: "stop.fill", role: .destructive) { model.requestStop() }
            case .onBreak:
                bigButton("End break", symbol: "play.fill", prominent: true) { model.timer.resume(); model.now = Date() }
                bigButton("Skip", symbol: "forward.fill") { model.timer.skipBreak(); model.now = Date() }
                bigButton("Snooze \(model.store.settings.snoozeMinutes) min", symbol: "clock.arrow.circlepath") { model.timer.snoozeBreak(); model.now = Date() }
            }
        }
        .animation(.smooth(duration: 0.25), value: phase)
    }

    private func bigButton(_ title: LocalizedStringKey, symbol: String, prominent: Bool = false,
                           role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        let button = Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(minWidth: 110)
                .padding(.vertical, 4)
        }
        .controlSize(.large)
        return Group {
            if prominent {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered).tint(role == .destructive ? .red : nil)
            }
        }
    }

    @ViewBuilder
    private var breakInfo: some View {
        let s = model.store.settings
        let timer = model.timer
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                if phase == .onBreak {
                    Label("Break ends at \(Fmt.time(model.store.runtime.breakEndsAt ?? model.now))", systemImage: "cup.and.saucer")
                } else if s.breaksEnabled, let left = timer.workUntilBreak(now: model.now) {
                    Label("Next break in \(Fmt.hm(left + 59))", systemImage: "hourglass")
                }
                if phase != .idle {
                    Label("Session: \(Fmt.hm(model.sessionWork)) work · \(Fmt.hm(timer.sessionBreakSeconds(now: model.now))) break", systemImage: "chart.pie")
                }
            }
            HStack(spacing: 12) {
                planMenu(s)
                if s.breaksEnabled {
                    // Current block: click to change this block's lengths on the fly.
                    Button { showBlockAdjust.toggle() } label: {
                        Label("Block \(timer.currentBlockNumber) · \(Int(timer.currentBlockWorkTarget / 60))/\(timer.currentBlockBreakMinutes) min",
                              systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                    .help("Adjust this block's work and break time")
                    .popover(isPresented: $showBlockAdjust, arrowEdge: .bottom) {
                        BlockAdjustPopover()
                    }
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    /// Plan menu: templates, custom plan, edit shortcuts.
    private func planMenu(_ s: AppSettings) -> some View {
        Menu {
            Toggle("Breaks on", isOn: Binding(get: { s.breaksEnabled }, set: { v in model.store.updateSettings { $0.breaksEnabled = v } }))
            Divider()
            Section("Templates") {
                ForEach(s.presets, id: \.id) { p in presetButton(p, activeID: s.activePreset.id) }
            }
            presetButton(s.customPreset, activeID: s.activePreset.id)
            Divider()
            Button("Set up custom plan…") { model.planEditor = PlanEditorRequest(presetID: BreakPreset.customID, activateOnSave: true) }
            Button("Edit active plan…") { model.planEditor = PlanEditorRequest(presetID: s.activePreset.id) }
            Button("New template…") { model.planEditor = PlanEditorRequest(presetID: nil, activateOnSave: true) }
            Divider()
            Button("Restart plan from first block") { model.timer.restartPlan(); model.now = Date() }
        } label: {
            Label("\(s.activePreset.isCustom ? String(localized: "Custom plan") : s.activePreset.name) · \(s.activePreset.summary)", systemImage: "timer")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Break plan")
    }

    private func presetButton(_ p: BreakPreset, activeID: UUID) -> some View {
        Button {
            model.selectPreset(p.id)
        } label: {
            let title = "\(p.isCustom ? String(localized: "Custom plan (no template)") : p.name) · \(p.summary)"
            if p.id == activeID { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private var noteField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Quick note… (⌘↩ to save)", text: $quickNote, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($noteFocused)
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            // The ⌘↩ shortcut is bound to this button (works while the field has focus too).
            Button("Save") { saveNote() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(quickNote.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func saveNote() {
        model.addQuickNote(quickNote)
        quickNote = ""
    }

    /// Notes taken in this session.
    @ViewBuilder
    private var sessionNotes: some View {
        let rt = model.store.runtime
        let sessionEntryIDs = Set(model.store.entries.filter { $0.sessionID != nil && $0.sessionID == rt.sessionID }.map(\.id))
        let notes = model.store.notes.filter { $0.entryID.map(sessionEntryIDs.contains) ?? false }.sorted { $0.createdAt > $1.createdAt }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes from this session").font(.headline)
                ForEach(notes) { n in
                    HStack(alignment: .top) {
                        Text(Fmt.time(n.createdAt)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(n.text).textSelection(.enabled)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Recent topics while idle: start with one click.
    @ViewBuilder
    private var recentList: some View {
        let recents = model.store.recentTargets(limit: 5)
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").font(.headline)
                ForEach(Array(recents.enumerated()), id: \.offset) { _, r in
                    RecentRow(projectID: r.projectID, topicID: r.topicID)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var phaseTitle: LocalizedStringKey {
        switch phase {
        case .idle: "Ready"
        case .working: "Working"
        case .paused: model.store.runtime.pausedBySystem ? "Paused because of sleep" : model.store.runtime.awaitingResumeAfterBreak ? "Break is over" : "Paused"
        case .onBreak: "Break"
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .idle: .secondary
        case .working: .green
        case .paused: .yellow
        case .onBreak: .orange
        }
    }
}

/// Row for a recent topic.
struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    let topicID: UUID?
    var compact = false

    var body: some View {
        Button {
            model.start(projectID: projectID, topicID: topicID)
        } label: {
            HStack(spacing: 8) {
                if let p = model.store.project(projectID) {
                    ProjectIconView(project: p, size: compact ? 18 : 22, images: model.store.images)
                }
                Text(model.store.pathString(projectID: projectID, topicID: topicID))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "play.circle.fill").foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, compact ? 3 : 6)
            .padding(.horizontal, compact ? 6 : 10)
            .contentShape(Rectangle())
            .background(.background.secondary.opacity(compact ? 0 : 1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Start: \(model.store.pathString(projectID: projectID, topicID: topicID))"))
    }
}

/// First-launch welcome screen.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            // App icon (time ring)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
            Text("Welcome to Athlos").font(.largeTitle.bold())
            Text("Create your projects and subtopics, start the timer, and let Athlos keep track of your daily goal, breaks and statistics. All data stays on this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            VStack(alignment: .leading, spacing: 10) {
                Label("Project → subtopic → subtopic… an unlimited tree", systemImage: "list.bullet.indent")
                Label("Break reminders and a 6-hour daily goal", systemImage: "cup.and.saucer")
                Label("Quick control from the menu bar and ⌃⌥Space", systemImage: "menubar.rectangle")
            }
            .font(.callout)
            Button {
                model.newProject()
            } label: {
                Label("Create your first project", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Athlos")
    }
}

/// Panel for changing the current block's lengths on the fly (the template doesn't change).
struct BlockAdjustPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let timer = model.timer
        VStack(alignment: .leading, spacing: 12) {
            Text("Block \(timer.currentBlockNumber) · \(model.store.settings.activePreset.isCustom ? String(localized: "Custom plan") : model.store.settings.activePreset.name)")
                .font(.headline)
            MinutesField(title: "Work", symbol: "hammer",
                         value: Binding(get: { Int((timer.currentBlockWorkTarget / 60).rounded()) },
                                        set: { timer.setCurrentBlockWorkMinutes($0); model.now = Date() }),
                         range: 1...600)
            MinutesField(title: "Break", symbol: "cup.and.saucer",
                         value: Binding(get: { timer.currentBlockBreakMinutes },
                                        set: { timer.setCurrentBlockBreakMinutes($0); model.now = Date() }),
                         range: 1...480)
            if let left = timer.workUntilBreak(now: model.now) {
                Text("\(Fmt.hm(timer.workInBlock(now: model.now))) worked in this block · break in \(Fmt.hm(left + 59))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Applies to this block only; the template doesn't change.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Start break now") { timer.startBreak(); model.now = Date() }
                    .disabled(!(timer.phase == .working || timer.phase == .paused))
                Button("Skip block") { timer.skipBreak(); model.now = Date() }
                    .help("Skip this block's break and move to the next block")
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 330)
    }
}
