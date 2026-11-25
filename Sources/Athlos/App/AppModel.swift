import SwiftUI
import AthlosCore

/// Sidebar pages.
enum Route: String, Hashable, CaseIterable, Identifiable {
    case timer, projects, stats, showcase, settings
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .timer: "Timer"
        case .projects: "Projects"
        case .stats: "Statistics"
        case .showcase: "Completed"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .timer: "timer"
        case .projects: "folder"
        case .stats: "chart.bar.xaxis"
        case .showcase: "trophy"
        case .settings: "gearshape"
        }
    }
}

/// Tree selection on the Projects page.
enum TreeSelection: Hashable {
    case project(UUID)
    case topic(UUID)
}

/// Request to create a new subtopic (in which project / under which parent).
struct NewTopicRequest: Identifiable {
    let id = UUID()
    let projectID: UUID
    let parentID: UUID?
}

/// Project editor request (nil → new project).
struct ProjectEditorRequest: Identifiable {
    let id = UUID()
    var project: Project?
    var startCompleted = false
}

/// Idle question.
struct IdlePrompt: Identifiable {
    let id = UUID()
    let idleSince: Date
}

/// The app's view model: store + timer + UI state + system services.
@MainActor
@Observable
final class AppModel {
    let paths: AppPaths
    let store: AppStore
    let timer: TimerService

    /// Updated every second; all live displays depend on it.
    var now = Date()

    // Navigation / page state
    var route: Route = .timer
    /// Selection binding of the sidebar List (List wants an optional selection; nil keeps the page).
    var sidebarSelection: Route? {
        get { route }
        set { if let newValue { route = newValue } }
    }
    var treeSelection: TreeSelection?
    var expandedNodes: Set<UUID> = []

    // Sheets / windows
    var showQuickPicker = false
    var quickPickerSwitchOnly = false
    var showStopSheet = false
    var projectEditor: ProjectEditorRequest?
    var planEditor: PlanEditorRequest?
    var newTopicRequest: NewTopicRequest?
    var recovery: RecoveryInfo?
    var idlePrompt: IdlePrompt?
    var celebrating = false
    var toast: String?

    @ObservationIgnored let notifications = NotificationService()
    /// Desktop widget (created at launch).
    @ObservationIgnored private(set) var desktopWidget: DesktopWidgetController?
    /// Data/command bridge to the macOS widgets.
    @ObservationIgnored private var widgetBridge: WidgetBridge?
    /// Is the widget visible (observable for the switches in the menu and Settings).
    var desktopWidgetVisible = false
    /// Widget size (the panel is rebuilt on change; its position is kept).
    var desktopWidgetSize: DesktopWidgetSize = .medium {
        didSet { if desktopWidget?.size != desktopWidgetSize { desktopWidget?.size = desktopWidgetSize } }
    }
    @ObservationIgnored private let hotKeys = HotKeyService()
    @ObservationIgnored private let system = SystemMonitor()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var tickCount = 0
    /// Registered by a window view; used to bring the main window to the front.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    init(paths: AppPaths = .standard) {
        self.paths = paths
        paths.ensureDirectories()
        let store = AppStore(persistence: JSONFilePersistence(url: paths.dataFile), images: ImageStore(directory: paths.imagesDir))
        DemoData.seedIfRequested(store)
        self.store = store
        self.timer = TimerService(store: store)
        self.recovery = timer.pendingRecovery()
        expandedNodes = Set(store.projects.map(\.id))
        DemoData.prepareUI(self)
        if store.projects.isEmpty { route = .timer }
    }

    // MARK: Lifecycle

    @ObservationIgnored private var launched = false

    /// Runs once at launch (whichever appears first: the main window or the menu bar).
    /// Note: idempotent, so the timer and shortcut also start in sessions where the main window never opens.
    func launch() {
        guard !launched else { return }
        launched = true
        notifications.setup()
        notifications.onAction = { [weak self] action in self?.handleNotification(action) }

        system.onSleep = { [weak self] in self?.timer.systemWillSleep() }
        system.onWake = { [weak self] in
            guard let self else { return }
            now = Date()
            handle(events: timer.systemDidWake())
        }
        system.start()
        applyHotKeySetting()
        BackupService.autoBackupIfNeeded(store: store, directory: paths.backupsDir)
        startTicking()
        let widget = DesktopWidgetController(model: self)
        desktopWidget = widget
        let bridge = WidgetBridge(model: self)
        widgetBridge = bridge
        bridge.start()
        desktopWidgetSize = widget.size
        widget.restore()
        desktopWidgetVisible = widget.isEnabled
    }

    /// athlos:// links: clicking a widget opens the matching page.
    func handle(url: URL) {
        guard url.scheme == "athlos" else { return }
        switch url.host() ?? "" {
        case "stats": route = .stats
        case "projects": route = .projects
        case "showcase": route = .showcase
        case "settings": route = .settings
        default: route = .timer
        }
        bringToFront()
    }

    /// Show / hide the desktop widget (the choice is remembered).
    func setDesktopWidget(visible: Bool) {
        desktopWidget?.setVisible(visible)
        desktopWidgetVisible = visible
    }

    func applyHotKeySetting() {
        if store.settings.globalHotKeyEnabled {
            hotKeys.register { [weak self] in self?.toggleOrPick(fromHotKey: true) }
        } else {
            hotKeys.unregister()
        }
    }

    /// A loop aligned to the next whole second. Durations are computed from timestamps, so a
    /// delay or sleep doesn't change the result; the loop only updates the screen and the threshold checks.
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let frac = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
                try? await Task.sleep(for: .seconds(1 - frac + 0.01))
                self?.onTick()
            }
        }
    }

    private func onTick() {
        now = Date()
        tickCount += 1
        guard recovery == nil else { return } // no threshold checks until the recovery question is answered
        handle(events: timer.tick())
        if tickCount % 30 == 0 { timer.heartbeat() }
        if tickCount % 5 == 0 { checkIdle() }
        if tickCount % 60 == 0 { BackupService.autoBackupIfNeeded(store: store, directory: paths.backupsDir) }
        checkGoal()
        widgetBridge?.update()
    }

    private func handle(events: [TimerEvent]) {
        for e in events {
            switch e {
            case .breakStarted:
                // The block hasn't advanced yet when the break starts: report the finished block's lengths.
                let workMin = Int((timer.currentBlockWorkTarget / 60).rounded())
                let breakMin = Int((timer.breakRemaining(now: Date()) / 60).rounded())
                if store.settings.notificationsEnabled { notifications.breakStarted(workMinutes: workMin, breakMinutes: breakMin) }
            case .breakEnded:
                if store.settings.notificationsEnabled { notifications.breakEnded() }
            }
        }
    }

    private func handleNotification(_ action: NotificationService.Action) {
        switch action {
        case .skipBreak: timer.skipBreak()
        case .snoozeBreak: timer.snoozeBreak()
        case .resumeWork, .endBreakNow: timer.resume()
        }
        now = Date()
    }

    // MARK: Idle detection

    private func checkIdle() {
        guard store.settings.idleDetectionEnabled, timer.phase == .working, idlePrompt == nil else { return }
        let idle = SystemMonitor.secondsSinceLastInput()
        let limit = TimeInterval(store.settings.idleMinutes * 60)
        guard idle >= limit else { return }
        idlePrompt = IdlePrompt(idleSince: Date().addingTimeInterval(-idle))
        if store.settings.notificationsEnabled { notifications.idle(minutes: Int(idle / 60)) }
        bringToFront()
    }

    func resolveIdle(discard: Bool) {
        if let p = idlePrompt, discard { timer.discardIdle(since: p.idleSince) }
        idlePrompt = nil
        now = Date()
    }

    // MARK: Goal celebration

    private func checkGoal() {
        let goal = store.settings.dailyGoalSeconds
        guard goal > 0, timer.phase == .working else { return }
        let today = Calendar.current.startOfDay(for: now)
        if let last = store.runtime.lastCelebratedDay, Calendar.current.isDate(last, inSameDayAs: today) { return }
        guard todayWork >= goal else { return }
        store.updateRuntime { $0.lastCelebratedDay = today }
        celebrate()
        if store.settings.notificationsEnabled { notifications.goalReached(hours: Fmt.hm(todayWork)) }
    }

    func celebrate() {
        celebrating = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            celebrating = false
        }
    }

    // MARK: Computed values

    var todayWork: TimeInterval { store.todayWorkSeconds(now: now) }
    var dailyGoal: TimeInterval { store.settings.dailyGoalSeconds }
    var sessionWork: TimeInterval { timer.sessionWorkSeconds(now: now) }
    var breakRemaining: TimeInterval { timer.breakRemaining(now: now) }

    /// Time shown on the main display: remaining break time while on a break, otherwise session work.
    var displaySeconds: TimeInterval { timer.phase == .onBreak ? breakRemaining : sessionWork }

    var activePath: [String] {
        store.pathComponents(projectID: store.runtime.projectID, topicID: store.runtime.topicID)
    }

    var activeProject: Project? { store.project(store.runtime.projectID) }

    var menuBarTitle: String {
        switch timer.phase {
        case .idle: ""
        case .working: "▶ " + Fmt.clock(sessionWork)
        case .paused: "❚❚ " + Fmt.clock(sessionWork)
        case .onBreak: "☕ " + Fmt.minSec(breakRemaining)
        }
    }

    // MARK: Actions

    func start(projectID: UUID, topicID: UUID?) {
        timer.start(projectID: projectID, topicID: topicID)
        now = Date()
    }

    /// Start/Pause; opens the quick picker if no topic is selected.
    func toggleOrPick(fromHotKey: Bool = false) {
        if timer.toggle() {
            now = Date()
            return
        }
        // If there is a recent topic, the shortcut starts it directly.
        if fromHotKey, let recent = store.recentTargets(limit: 1).first {
            start(projectID: recent.projectID, topicID: recent.topicID)
            return
        }
        openQuickPicker()
        if fromHotKey { bringToFront() }
    }

    func openQuickPicker(switchOnly: Bool = false) {
        quickPickerSwitchOnly = switchOnly
        showQuickPicker = true
    }

    func pick(projectID: UUID, topicID: UUID?) {
        showQuickPicker = false
        if timer.phase != .idle, quickPickerSwitchOnly {
            timer.switchTarget(projectID: projectID, topicID: topicID)
        } else {
            start(projectID: projectID, topicID: topicID)
        }
        now = Date()
    }

    func requestStop() {
        guard timer.phase != .idle else { return }
        if store.settings.askNoteOnStop {
            showStopSheet = true
            bringToFront()
        } else {
            timer.stop()
        }
    }

    func finishStop(note: String?) {
        showStopSheet = false
        timer.stop(note: note)
        now = Date()
    }

    /// Quick note while working: linked to the active topic and the open entry.
    func addQuickNote(_ text: String) {
        let rt = store.runtime
        guard let pid = rt.projectID else { return }
        let entryID = store.entries.last { $0.sessionID == rt.sessionID && $0.kind == .work }?.id
        if store.addNote(text, projectID: pid, topicID: rt.topicID, entryID: entryID) != nil {
            showToast(String(localized: "Note saved"))
        }
    }

    func showToast(_ text: String) {
        withAnimation { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { if toast == text { toast = nil } }
        }
    }

    /// Changes the break plan; the new plan starts from its first block.
    func selectPreset(_ id: UUID) {
        guard id != store.settings.activePreset.id else { return }
        store.updateSettings { $0.activePresetID = id }
        timer.restartPlan()
        now = Date()
    }

    func newProject() { projectEditor = ProjectEditorRequest(project: nil) }

    /// New topic under the selected node (or under the first active project if nothing is selected).
    func newTopic() {
        switch treeSelection {
        case .project(let pid): newTopicRequest = NewTopicRequest(projectID: pid, parentID: nil)
        case .topic(let tid):
            if let t = store.topic(tid) { newTopicRequest = NewTopicRequest(projectID: t.projectID, parentID: t.id) }
        case nil:
            if let pid = store.runtime.projectID ?? store.projects(status: .active).first?.id {
                newTopicRequest = NewTopicRequest(projectID: pid, parentID: store.runtime.projectID == pid ? store.runtime.topicID : nil)
            } else {
                newProject()
                return
            }
        }
        route = .projects
    }

    // MARK: Recovery

    func resolveRecovery(_ choice: RecoveryChoice) {
        guard let info = recovery else { return }
        switch choice {
        case .continue: timer.recoverContinue()
        case .finishAtLastAlive: timer.recoverFinish(at: info.lastAlive ?? info.startedAt)
        case .finishNow: timer.recoverFinish(at: Date())
        }
        recovery = nil
        now = Date()
    }

    enum RecoveryChoice { case `continue`, finishAtLastAlive, finishNow }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        openMainWindow?()
    }
}
