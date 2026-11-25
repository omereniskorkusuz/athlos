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
            VStack(spacing: 18) {
                Spacer(minLength: 18)
                header
                clock
                blockProgress
                controls
                    .padding(.top, 8)
                planRow
                VStack(spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        GoalRingCard()
                        if phase != .idle { noteCard }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if phase == .idle { recentList }
                    sessionNotes
                }
                .padding(.top, 22)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 36)
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

    /// Path + state chip, then the topic name in serif. Clicking either opens the topic picker (⌘K).
    private var header: some View {
        Button {
            model.openQuickPicker(switchOnly: phase != .idle)
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    if let p = model.activeProject {
                        ProjectIconView(project: p, size: 18, images: model.store.images)
                        ForEach(Array(model.activePath.dropLast().enumerated()), id: \.offset) { i, part in
                            if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.inkTertiary) }
                            Text(part)
                        }
                    }
                    HStack(spacing: 6) {
                        Circle().fill(phaseColor).frame(width: 6, height: 6)
                        Text(phaseTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .contentTransition(.opacity)
                    }
                    .foregroundStyle(phase == .working ? Theme.goldText : phase == .onBreak ? Theme.rest : Theme.inkSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(phase == .working ? Theme.goldSoft : Theme.track.opacity(0.6), in: Capsule())
                    .padding(.leading, model.activeProject == nil ? 0 : 6)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSecondary)

                Text(model.activePath.last ?? String(localized: "Choose topic"))
                    .font(Theme.display(44))
                    .foregroundStyle(model.activeProject == nil ? Theme.inkSecondary : Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Choose topic (⌘K)")
        .accessibilityLabel(Text("Active topic: \(model.activePath.joined(separator: ", "))"))
    }

    private var clock: some View {
        Text(Fmt.clock(model.displaySeconds))
            .font(.system(size: 104, weight: .thin))
            .monospacedDigit()
            .tracking(-2)
            .contentTransition(.numericText(countsDown: phase == .onBreak))
            .animation(.smooth(duration: 0.3), value: Int(model.displaySeconds))
            .foregroundStyle(phase == .paused ? Theme.inkSecondary : phase == .onBreak ? Theme.rest : Theme.ink)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .accessibilityLabel(phase == .onBreak ? Text("\(Fmt.spoken(model.displaySeconds)) left in break") : Text("Elapsed \(Fmt.spoken(model.displaySeconds))"))
    }

    /// The day's plan as hairline segments (one per work block); the current block fills with gold.
    @ViewBuilder
    private var blockProgress: some View {
        let s = model.store.settings
        let timer = model.timer
        if s.breaksEnabled {
            let preset = s.activePreset
            let blocks = preset.blocks.isEmpty ? [PlanBlock(workMinutes: 50, breakMinutes: 10)] : preset.blocks
            let index = timer.currentBlockNumber - 1
            let shown = preset.afterLast == .cycle ? index % blocks.count : min(index, blocks.count - 1)
            let target = max(timer.currentBlockWorkTarget, 1)
            let done = phase == .idle ? 0 : min(timer.workInBlock(now: model.now) / target, 1)
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.track)
                                let fill: CGFloat = i < shown && phase != .idle ? 1 : (i == shown ? done : 0)
                                if fill > 0 {
                                    Capsule().fill(Theme.goldGradient).frame(width: max(6, geo.size.width * fill))
                                }
                            }
                        }
                        .frame(height: 6)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(Double(b.workMinutes))
                    }
                }
                .animation(.smooth(duration: 0.6), value: done)
                HStack {
                    Text(phase == .idle
                         ? String(localized: "\(blocks.count) blocks · \(preset.summary)")
                         : String(localized: "Block \(timer.currentBlockNumber) · \(Fmt.hm(timer.workInBlock(now: model.now))) of \(Fmt.hm(timer.currentBlockWorkTarget))"))
                        .monospacedDigit()
                    Spacer()
                    if phase == .onBreak {
                        Label("Break ends at \(Fmt.time(model.store.runtime.breakEndsAt ?? model.now))", systemImage: "cup.and.saucer")
                    } else if let left = timer.workUntilBreak(now: model.now) {
                        Label("Next break in \(Fmt.hm(left + 59))", systemImage: "hourglass")
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
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

    @ViewBuilder
    private func bigButton(_ title: LocalizedStringKey, symbol: String, prominent: Bool = false,
                           role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        let label = Label(title, systemImage: symbol).labelStyle(PillLabelStyle(iconColor: prominent ? Theme.goldBright : nil))
        if prominent {
            Button(role: role, action: action) { label }.buttonStyle(PrimaryPillStyle(minWidth: 112))
        } else {
            Button(role: role, action: action) { label }.buttonStyle(SecondaryPillStyle(minWidth: 112))
        }
    }

    /// Plan menu, block adjustment and session totals in one quiet row.
    @ViewBuilder
    private var planRow: some View {
        let s = model.store.settings
        let timer = model.timer
        HStack(spacing: 14) {
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
            if phase != .idle {
                Label("Session: \(Fmt.hm(model.sessionWork)) work · \(Fmt.hm(timer.sessionBreakSeconds(now: model.now))) break", systemImage: "chart.pie")
            }
        }
        .font(.callout)
        .foregroundStyle(Theme.inkSecondary)
        .tint(Theme.inkSecondary)
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

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Session notes").font(.system(size: 12.5)).foregroundStyle(Theme.inkSecondary)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Quick note… (⌘↩ to save)", text: $quickNote, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($noteFocused)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Theme.well, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
                // The ⌘↩ shortcut is bound to this button (works while the field has focus too).
                Button("Save") { saveNote() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(quickNote.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .athlosCard()
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Notes from this session").font(Theme.heading).foregroundStyle(Theme.ink)
                ForEach(notes) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Fmt.time(n.createdAt)).font(.caption.monospacedDigit()).foregroundStyle(Theme.inkSecondary)
                        Text(n.text).foregroundStyle(Theme.ink).textSelection(.enabled)
                        Spacer()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .athlosCard()
        }
    }

    /// Recent topics while idle: start with one click.
    @ViewBuilder
    private var recentList: some View {
        let recents = model.store.recentTargets(limit: 5)
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").font(Theme.heading).foregroundStyle(Theme.ink)
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
        case .idle: Theme.inkTertiary
        case .working: Theme.gold
        case .paused: Theme.paused
        case .onBreak: Theme.rest
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
                Image(systemName: "play.circle.fill").foregroundStyle(Theme.goldText)
            }
            .foregroundStyle(Theme.ink)
            .padding(.vertical, compact ? 3 : 9)
            .padding(.horizontal, compact ? 6 : 12)
            .contentShape(Rectangle())
            .background {
                if !compact {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
                }
            }
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
            AthlosLogo(size: 116)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                .accessibilityHidden(true)
            Text("Welcome to Athlos").font(Theme.display(38, weight: .bold)).foregroundStyle(Theme.ink)
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
            .foregroundStyle(Theme.ink)
            .tint(Theme.goldText)
            Button {
                model.newProject()
            } label: {
                Label("Create your first project", systemImage: "plus")
            }
            .buttonStyle(PrimaryPillStyle())
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

/// Icon + title for the pill buttons (the icon can be tinted separately, e.g. gold on the dark pill).
struct PillLabelStyle: LabelStyle {
    var iconColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.foreground))
            configuration.title
        }
    }
}

/// Daily goal as a gold ring with the time in serif (Timer screen).
struct GoalRingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let work = model.todayWork
        let goal = max(model.dailyGoal, 1)
        let progress = work / goal
        let reached = progress >= 1
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(progress, 1))
                    .stroke(AngularGradient(colors: [Theme.goldDeep, Theme.gold, Theme.goldBright], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(min(progress, 1), 0.01))),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: reached ? Theme.goldBright.opacity(0.6) : .clear, radius: 4)
                Image(systemName: reached ? "checkmark.seal.fill" : "target")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.goldText)
            }
            .frame(width: 60, height: 60)
            .animation(.smooth(duration: 0.6), value: progress)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Daily goal")
                    Text(verbatim: "· " + progress.formatted(.percent.precision(.fractionLength(0)).locale(Fmt.numberLocale)))
                        .monospacedDigit()
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Fmt.hm(work)).font(Theme.display(28)).foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text(verbatim: "/ " + Fmt.hm(goal)).font(.system(size: 14)).foregroundStyle(Theme.inkSecondary)
                }
                .monospacedDigit()
                Text(reached ? String(localized: "\(Fmt.hm(work - goal)) over your goal") : String(localized: "\(Fmt.hm(goal - work)) to go"))
                    .font(.system(size: 12))
                    .foregroundStyle(reached ? Theme.goldText : Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlosCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily goal")
        .accessibilityValue(Text("\(Fmt.spoken(work)) / \(Fmt.spoken(goal))"))
    }
}
