import Foundation

// MARK: - Time source (injectable for tests)

public protocol TimeSource: Sendable {
    func now() -> Date
}

public struct SystemTimeSource: TimeSource {
    public init() {}
    public func now() -> Date { Date() }
}

/// For moving time by hand in tests.
public final class ManualTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date) { current = start }

    public func now() -> Date { lock.withLock { current } }
    public func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    public func set(_ date: Date) { lock.withLock { current = date } }
}

// MARK: - Events

/// Events from `tick()` that the UI must react to (notifications etc.).
public enum TimerEvent: Equatable, Sendable {
    case breakStarted(endsAt: Date)
    case breakEnded
}

/// Found at launch: an unfinished entry (one without an end).
public struct RecoveryInfo: Equatable, Sendable {
    public var entryID: UUID
    public var kind: EntryKind
    public var startedAt: Date
    /// The last moment the app was alive (nil if unknown).
    public var lastAlive: Date?
}

// MARK: - TimerService

/// Timer logic. No time is kept by counting ticks; everything is computed from the entries' timestamps.
/// So durations stay correct even if the Mac sleeps or the app quits or crashes.
/// `tick()` is only for threshold checks (is it time for a break, etc.); a missed tick changes nothing.
@MainActor
public final class TimerService {
    public let store: AppStore
    public let clock: TimeSource

    public init(store: AppStore, clock: TimeSource = SystemTimeSource()) {
        self.store = store
        self.clock = clock
    }

    private var rt: RuntimeState { store.runtime }
    private var preset: BreakPreset { store.settings.activePreset }

    /// Calendar used for day boundaries (replaceable in tests).
    public var calendar: Calendar = .current

    public var phase: TimerPhase { rt.phase }
    public var isActive: Bool { rt.phase != .idle }

    // MARK: Computed values

    /// Total work time in this session (breaks excluded).
    public func sessionWorkSeconds(now: Date? = nil) -> TimeInterval {
        guard let sid = rt.sessionID else { return 0 }
        let n = now ?? clock.now()
        return store.entries.lazy.filter { $0.sessionID == sid && $0.kind == .work }.reduce(0) { $0 + $1.duration(now: n) }
    }

    /// Total break time in this session.
    public func sessionBreakSeconds(now: Date? = nil) -> TimeInterval {
        guard let sid = rt.sessionID else { return 0 }
        let n = now ?? clock.now()
        return store.entries.lazy.filter { $0.sessionID == sid && $0.kind == .breakTime }.reduce(0) { $0 + $1.duration(now: n) }
    }

    /// Time left in the break.
    public func breakRemaining(now: Date? = nil) -> TimeInterval {
        guard rt.phase == .onBreak, let end = rt.breakEndsAt else { return 0 }
        return max(0, end.timeIntervalSince(now ?? clock.now()))
    }

    // MARK: Daily plan (blocks)

    /// The day's current block (work/break lengths). Quick adjustments are not included.
    public var currentBlock: PlanBlock { preset.block(at: rt.blockIndex) }

    /// Block number starting at 1.
    public var currentBlockNumber: Int { rt.blockIndex + 1 }

    /// This block's target work time (including snooze / quick adjustments).
    public var currentBlockWorkTarget: TimeInterval {
        max(60, currentBlock.workSeconds + rt.blockExtraSeconds)
    }

    /// This block's break length (min; including quick adjustments).
    public var currentBlockBreakMinutes: Int { rt.breakMinutesOverride ?? currentBlock.breakMinutes }

    /// Work done in this block so far. Kept across sessions: every work entry recorded since
    /// the block started is counted (gaps in between are not).
    public func workInBlock(now: Date? = nil) -> TimeInterval {
        guard let s = rt.blockStartedAt else { return 0 }
        let n = now ?? clock.now()
        guard n > s else { return 0 }
        return Stats.seconds(store.entries, kind: .work, in: DateInterval(start: s, end: n), now: n)
    }

    /// Work time left until the next break.
    public func workUntilBreak(now: Date? = nil) -> TimeInterval? {
        guard store.settings.breaksEnabled, rt.phase == .working || rt.phase == .paused else { return nil }
        return max(0, currentBlockWorkTarget - workInBlock(now: now))
    }

    /// On a new day the plan starts from the first block; if the block has no start yet, it starts now.
    private func ensurePlanDay(now: Date) {
        let today = calendar.startOfDay(for: now)
        let sameDay = rt.planDay.map { calendar.isDate($0, inSameDayAs: today) } ?? false
        if !sameDay {
            store.updateRuntime(save: false) { r in
                r.planDay = today
                r.blockIndex = 0
                r.blockStartedAt = now
                r.blockExtraSeconds = 0
                r.breakMinutesOverride = nil
            }
        } else if rt.blockStartedAt == nil {
            store.updateRuntime(save: false) { $0.blockStartedAt = now }
        }
    }

    /// Move on to the next block (when a break ends or is skipped).
    private func advanceBlock(at date: Date) {
        store.updateRuntime(save: false) { r in
            r.blockIndex += 1
            r.blockStartedAt = date
            r.blockExtraSeconds = 0
            r.breakMinutesOverride = nil
        }
    }

    /// Changes the current block's work length (min) on the fly. The plan template doesn't change.
    public func setCurrentBlockWorkMinutes(_ minutes: Int) {
        let target = TimeInterval(max(1, minutes) * 60)
        let extra = target - currentBlock.workSeconds
        store.updateRuntime { $0.blockExtraSeconds = extra }
    }

    /// Changes the current block's break length (min) on the fly. During a break the end time is updated too.
    public func setCurrentBlockBreakMinutes(_ minutes: Int) {
        let m = max(1, minutes)
        let breakStart = rt.phase == .onBreak ? store.openEntry.flatMap { $0.kind == .breakTime ? $0.start : nil } : nil
        store.updateRuntime { r in
            r.breakMinutesOverride = m
            if let breakStart { r.breakEndsAt = breakStart.addingTimeInterval(TimeInterval(m * 60)) }
        }
    }

    /// Restarts the plan from the first block (e.g. when the template changes).
    public func restartPlan() {
        let now = clock.now()
        store.updateRuntime { r in
            r.planDay = self.calendar.startOfDay(for: now)
            r.blockIndex = 0
            r.blockStartedAt = now
            r.blockExtraSeconds = 0
            r.breakMinutesOverride = nil
        }
    }

    /// Fields kept when the session state is reset (including the daily plan progress).
    private static func freshState(keeping r: RuntimeState) -> RuntimeState {
        var n = RuntimeState()
        n.lastCelebratedDay = r.lastCelebratedDay
        n.lastAutoBackupDay = r.lastAutoBackupDay
        n.planDay = r.planDay
        n.blockIndex = r.blockIndex
        n.blockStartedAt = r.blockStartedAt
        n.blockExtraSeconds = r.blockExtraSeconds
        n.breakMinutesOverride = r.breakMinutesOverride
        return n
    }

    // MARK: Basic actions

    /// Starts a new session. Stops the running session first, if any.
    /// Plan progress within the day is kept (you continue from the block you were on).
    public func start(projectID: UUID, topicID: UUID?) {
        if rt.phase != .idle { stop() }
        let now = clock.now()
        store.updateRuntime(save: false) { r in
            r = Self.freshState(keeping: r)
            r.phase = .working
            r.sessionID = UUID()
            r.projectID = projectID
            r.topicID = topicID
            r.lastHeartbeat = now
        }
        ensurePlanDay(now: now)
        openEntry(kind: .work, at: now)
    }

    /// Closes the running entry, keeps the session.
    public func pause(at date: Date? = nil, bySystem: Bool = false) {
        guard rt.phase == .working else { return }
        closeOpenEntry(at: date ?? clock.now())
        store.updateRuntime { r in
            r.phase = .paused
            r.pausedBySystem = bySystem
        }
    }

    public func resume() {
        switch rt.phase {
        case .paused:
            store.updateRuntime(save: false) { r in
                r.phase = .working
                r.awaitingResumeAfterBreak = false
                r.pausedBySystem = false
            }
            ensurePlanDay(now: clock.now())
            openEntry(kind: .work, at: clock.now())
        case .onBreak:
            endBreak(resumeWork: true)
        default:
            break
        }
    }

    /// Space / global shortcut. Returns `false` if no topic is selected (the UI opens the quick picker).
    @discardableResult
    public func toggle() -> Bool {
        switch rt.phase {
        case .idle: return false
        case .working: pause()
        case .paused, .onBreak: resume()
        }
        return true
    }

    /// Stops the session. A note, if given, is linked to the last work entry and the topic.
    @discardableResult
    public func stop(note: String? = nil) -> UUID? {
        guard rt.phase != .idle else { return nil }
        let now = clock.now()
        // Stopping during a break counts the break as done; the plan moves on to the next block.
        let wasOnBreak = rt.phase == .onBreak
        closeOpenEntry(at: min(now, rt.breakEndsAt ?? now))
        if wasOnBreak { advanceBlock(at: now) }
        let sid = rt.sessionID
        let lastWork = store.entries.last { $0.sessionID == sid && $0.kind == .work }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.addNote(note, projectID: rt.projectID, topicID: rt.topicID, entryID: lastWork?.id, at: now)
        }
        store.updateRuntime { r in r = Self.freshState(keeping: r) }
        return lastWork?.id
    }

    /// Changes the active topic without breaking the session (opens a new entry if working).
    public func switchTarget(projectID: UUID, topicID: UUID?) {
        guard rt.phase != .idle else { start(projectID: projectID, topicID: topicID); return }
        let wasWorking = rt.phase == .working
        if wasWorking { closeOpenEntry(at: clock.now()) }
        store.updateRuntime(save: !wasWorking) { r in
            r.projectID = projectID
            r.topicID = topicID
        }
        if wasWorking { openEntry(kind: .work, at: clock.now()) }
    }

    // MARK: Breaks

    /// Starts a break (manual or automatic). Length: this block's break (or the given minutes).
    /// Breaks are kept as separate `.breakTime` entries and don't count as work.
    public func startBreak(at date: Date? = nil, minutes: Int? = nil) {
        guard rt.phase == .working || rt.phase == .paused, rt.projectID != nil else { return }
        let now = date ?? clock.now()
        closeOpenEntry(at: now)
        let length = TimeInterval(max(1, minutes ?? currentBlockBreakMinutes) * 60)
        store.updateRuntime(save: false) { r in
            r.phase = .onBreak
            r.breakEndsAt = now.addingTimeInterval(length)
            r.awaitingResumeAfterBreak = false
            r.pausedBySystem = false
        }
        openEntry(kind: .breakTime, at: now)
    }

    /// Ends the break and moves to the plan's next block.
    /// `resumeWork == false` → waits paused for "shall we continue?".
    public func endBreak(resumeWork: Bool, at date: Date? = nil) {
        guard rt.phase == .onBreak else { return }
        let now = date ?? clock.now()
        // If ended after the planned end, the extra time doesn't count as break (correct even while the app was closed).
        let end = min(now, rt.breakEndsAt ?? now)
        closeOpenEntry(at: end)
        advanceBlock(at: end)
        store.updateRuntime(save: false) { r in
            r.breakEndsAt = nil
            r.phase = resumeWork ? .working : .paused
            r.awaitingResumeAfterBreak = !resumeWork
        }
        if resumeWork { openEntry(kind: .work, at: now) } else { store.save() }
    }

    /// Skip break: (on a break) the break entry is deleted, work resumes and the plan's next block starts.
    public func skipBreak() {
        let now = clock.now()
        if rt.phase == .onBreak { cancelBreakAndResume(at: now) }
        guard rt.phase == .working || rt.phase == .paused else { return }
        advanceBlock(at: now)
        store.save()
    }

    /// Snooze the break (5 min by default): work this much longer in the same block.
    public func snoozeBreak(minutes: Int? = nil) {
        let now = clock.now()
        let seconds = TimeInterval((minutes ?? store.settings.snoozeMinutes) * 60)
        if rt.phase == .onBreak { cancelBreakAndResume(at: now) }
        guard rt.phase == .working || rt.phase == .paused else { return }
        // Threshold = block work so far + snooze
        let extra = max(rt.blockExtraSeconds, workInBlock(now: now) - currentBlock.workSeconds) + seconds
        store.updateRuntime { $0.blockExtraSeconds = extra }
    }

    /// Removes the unused break from the entries and goes back to work.
    private func cancelBreakAndResume(at now: Date) {
        if let open = store.openEntry, open.kind == .breakTime { store.deleteEntry(open.id) }
        store.updateRuntime(save: false) { r in
            r.phase = .working
            r.breakEndsAt = nil
        }
        openEntry(kind: .work, at: now)
    }

    // MARK: Periodic check

    /// Called once a second (or on wake). Only checks thresholds.
    @discardableResult
    public func tick() -> [TimerEvent] {
        let now = clock.now()
        var events: [TimerEvent] = []
        if rt.phase == .working || rt.phase == .paused { ensurePlanDay(now: now) }
        switch rt.phase {
        case .working:
            if store.settings.breaksEnabled, workInBlock(now: now) >= currentBlockWorkTarget {
                startBreak(at: now)
                if let end = rt.breakEndsAt { events.append(.breakStarted(endsAt: end)) }
            }
        case .onBreak:
            if let end = rt.breakEndsAt, now >= end {
                endBreak(resumeWork: false, at: now)
                events.append(.breakEnded)
            }
        default:
            break
        }
        return events
    }

    /// Records that the app is alive (for "end here" after a crash).
    public func heartbeat() {
        guard rt.phase != .idle else { return }
        store.updateRuntime { $0.lastHeartbeat = clock.now() }
    }

    // MARK: Sleep / lock / idle

    /// When the Mac goes to sleep. If the setting is "pause", the entry is closed at that moment.
    public func systemWillSleep(at date: Date? = nil) {
        guard store.settings.sleepBehavior == .pause, rt.phase == .working else { return }
        pause(at: date ?? clock.now(), bySystem: true)
    }

    /// On wake: the state is already correct from the timestamps; only the thresholds are checked.
    @discardableResult
    public func systemDidWake() -> [TimerEvent] { tick() }

    /// Removes idle time from work: the open entry is closed at the moment idling started and a new one opens now.
    public func discardIdle(since idleStart: Date) {
        guard rt.phase == .working, var open = store.openEntry, open.kind == .work else { return }
        let now = clock.now()
        if idleStart > open.start {
            open.end = idleStart
            store.updateEntry(open, save: false)
        } else {
            // If idling started before this entry began, the whole entry was idle.
            store.deleteEntry(open.id)
        }
        openEntry(kind: .work, at: now)
    }

    // MARK: Recovery

    /// Is there an entry without an end at launch?
    public func pendingRecovery() -> RecoveryInfo? {
        guard let open = store.openEntry else { return nil }
        return RecoveryInfo(entryID: open.id, kind: open.kind, startedAt: open.start, lastAlive: rt.lastHeartbeat)
    }

    /// Continue the unfinished session where it left off (the time in between counts).
    public func recoverContinue() {
        guard let open = store.openEntry else { return }
        let breakLength = TimeInterval(currentBlockBreakMinutes * 60)
        store.updateRuntime { r in
            if r.sessionID == nil { r.sessionID = open.sessionID ?? UUID() }
            r.projectID = r.projectID ?? open.projectID
            r.topicID = r.topicID ?? open.topicID
            if r.phase == .idle || r.phase == .paused { r.phase = open.kind == .work ? .working : .onBreak }
            if r.phase == .onBreak, r.breakEndsAt == nil {
                r.breakEndsAt = open.start.addingTimeInterval(breakLength)
            }
        }
        tick()
    }

    /// Ends the unfinished session at the given moment (usually the last "alive" moment).
    public func recoverFinish(at date: Date) {
        guard let open = store.openEntry else { return }
        let end = max(open.start, min(date, clock.now()))
        closeOpenEntry(at: end)
        store.updateRuntime { r in r = Self.freshState(keeping: r) }
    }

    // MARK: Helpers

    private func openEntry(kind: EntryKind, at date: Date) {
        guard let pid = rt.projectID else { return }
        store.addEntry(TimeEntry(projectID: pid, topicID: rt.topicID, kind: kind, start: date, sessionID: rt.sessionID))
    }

    /// Entries closed shorter than this (e.g. start → pause right away) are deleted so they don't clutter the history.
    static let minimumEntryDuration: TimeInterval = 1

    private func closeOpenEntry(at date: Date) {
        for e in store.entries where e.isRunning {
            var closed = e
            closed.end = max(e.start, date)
            if closed.duration(now: date) < Self.minimumEntryDuration {
                store.deleteEntry(e.id)
            } else {
                store.updateEntry(closed, save: false)
            }
        }
        store.save()
    }
}
