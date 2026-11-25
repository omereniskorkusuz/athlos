import Foundation

// MARK: - Project

/// Project icon: an emoji, an SF Symbol or an image copied into the app folder.
public enum ProjectIcon: Codable, Hashable, Sendable {
    case emoji(String)
    case symbol(String)
    /// File name in the `ImageStore` folder (e.g. "3F2A….png").
    case image(String)

    public static let `default` = ProjectIcon.symbol("folder.fill")
}

public enum ProjectStatus: String, Codable, Hashable, Sendable {
    case active
    case completed
}

/// The main thing you work on.
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: ProjectIcon
    /// Color in "#RRGGBB" form.
    public var colorHex: String
    public var status: ProjectStatus
    public var createdAt: Date
    public var completedAt: Date?
    /// Time spent before, outside the app, entered by hand (seconds). Added to the totals.
    public var manualSeconds: TimeInterval
    public var sortIndex: Int

    public init(id: UUID = UUID(), name: String, icon: ProjectIcon = .default, colorHex: String = "#0A84FF",
                status: ProjectStatus = .active, createdAt: Date = Date(), completedAt: Date? = nil,
                manualSeconds: TimeInterval = 0, sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.manualSeconds = manualSeconds
        self.sortIndex = sortIndex
    }
}

// MARK: - Topic (tree node)

/// A topic under a project; topics can be nested to any depth.
/// The tree is kept in a flat array with `parentID` (root nodes have `parentID == nil`).
public struct Topic: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var parentID: UUID?
    public var name: String
    public var sortIndex: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), projectID: UUID, parentID: UUID? = nil, name: String,
                sortIndex: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.projectID = projectID
        self.parentID = parentID
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

// MARK: - Time entry

public enum EntryKind: String, Codable, Hashable, Sendable, CaseIterable {
    case work
    case breakTime = "break"
}

/// A single uninterrupted period of work or break.
/// If `end == nil` the entry is still running; the duration is always computed from the `start` timestamp.
public struct TimeEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var topicID: UUID?
    public var kind: EntryKind
    public var start: Date
    public var end: Date?
    /// Entries of the same "session" (start → stop) share a sessionID (pause/resume creates separate entries).
    public var sessionID: UUID?
    public var isManual: Bool

    public init(id: UUID = UUID(), projectID: UUID, topicID: UUID?, kind: EntryKind = .work,
                start: Date, end: Date? = nil, sessionID: UUID? = nil, isManual: Bool = false) {
        self.id = id
        self.projectID = projectID
        self.topicID = topicID
        self.kind = kind
        self.start = start
        self.end = end
        self.sessionID = sessionID
        self.isManual = isManual
    }

    public var isRunning: Bool { end == nil }

    /// Duration of the entry at `now` (never negative).
    public func duration(now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }

    /// Duration of the part of the entry inside the given interval (entries crossing a day boundary are split correctly).
    public func duration(in interval: DateInterval, now: Date) -> TimeInterval {
        let s = max(start, interval.start)
        let e = min(end ?? now, interval.end)
        return max(0, e.timeIntervalSince(s))
    }
}

// MARK: - Note

/// A short plain-text note linked to a subtopic, a project or a time entry.
public struct Note: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var projectID: UUID?
    public var topicID: UUID?
    public var entryID: UUID?

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date(), projectID: UUID?,
                topicID: UUID?, entryID: UUID? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.projectID = projectID
        self.topicID = topicID
        self.entryID = entryID
    }
}

// MARK: - Settings

/// One work period followed by a break (e.g. work 75 min, break 15 min).
public struct PlanBlock: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var workMinutes: Int
    public var breakMinutes: Int

    public init(id: UUID = UUID(), workMinutes: Int, breakMinutes: Int) {
        self.id = id
        self.workMinutes = workMinutes
        self.breakMinutes = breakMinutes
    }

    public var workSeconds: TimeInterval { TimeInterval(max(1, workMinutes) * 60) }
    public var breakSeconds: TimeInterval { TimeInterval(max(0, breakMinutes) * 60) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        workMinutes = try c.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 50
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 10
    }
}

/// What happens after the last block.
public enum PlanRepeat: String, Codable, Hashable, Sendable, CaseIterable {
    /// The last block repeats (classic single-block templates work this way).
    case repeatLast
    /// The plan starts over.
    case cycle
}

/// Break template = work/break blocks applied in order.
/// E.g. "My workday": 75/15 → 60/10 → 50/60. A single-block template (50/10) is the classic repeating plan.
/// The plan is daily: if you stop and start again later the same day you continue from the block you were on;
/// the next day starts from the first block.
public struct BreakPreset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var blocks: [PlanBlock]
    public var afterLast: PlanRepeat

    public init(id: UUID = UUID(), name: String, blocks: [PlanBlock], afterLast: PlanRepeat = .repeatLast) {
        self.id = id
        self.name = name
        self.blocks = blocks
        self.afterLast = afterLast
    }

    /// Single-block (classic) template.
    public init(id: UUID = UUID(), name: String, workMinutes: Int, breakMinutes: Int) {
        self.init(id: id, name: name, blocks: [PlanBlock(workMinutes: workMinutes, breakMinutes: breakMinutes)])
    }

    /// The day's `index`-th block (from 0). Past the last block the `afterLast` rule applies.
    public func block(at index: Int) -> PlanBlock {
        guard !blocks.isEmpty else { return PlanBlock(workMinutes: 50, breakMinutes: 10) }
        let i = max(0, index)
        if i < blocks.count { return blocks[i] }
        switch afterLast {
        case .repeatLast: return blocks[blocks.count - 1]
        case .cycle: return blocks[i % blocks.count]
        }
    }

    /// Lengths of the first block (for compatibility and short labels).
    public var workMinutes: Int { block(at: 0).workMinutes }
    public var breakMinutes: Int { block(at: 0).breakMinutes }
    public var workSeconds: TimeInterval { block(at: 0).workSeconds }
    public var breakSeconds: TimeInterval { block(at: 0).breakSeconds }

    /// "75/15 → 60/10 → 50/60"
    public var summary: String {
        blocks.map { "\($0.workMinutes)/\($0.breakMinutes)" }.joined(separator: " → ")
    }

    private enum CodingKeys: String, CodingKey { case id, name, blocks, afterLast, workMinutes, breakMinutes }

    /// The old format ({workMinutes, breakMinutes}) is turned into a single-block template.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Template"
        if let b = try c.decodeIfPresent([PlanBlock].self, forKey: .blocks), !b.isEmpty {
            blocks = b
        } else {
            let w = try c.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 50
            let br = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 10
            blocks = [PlanBlock(workMinutes: w, breakMinutes: br)]
        }
        afterLast = try c.decodeIfPresent(PlanRepeat.self, forKey: .afterLast) ?? .repeatLast
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(afterLast, forKey: .afterLast)
    }

    public static let defaults: [BreakPreset] = [
        BreakPreset(name: "Pomodoro", workMinutes: 25, breakMinutes: 5),
        BreakPreset(name: "Classic", workMinutes: 50, breakMinutes: 10),
        BreakPreset(name: "Deep work", workMinutes: 90, breakMinutes: 20),
        BreakPreset(name: "Daily flow", blocks: [
            PlanBlock(workMinutes: 75, breakMinutes: 15),
            PlanBlock(workMinutes: 60, breakMinutes: 10),
            PlanBlock(workMinutes: 50, breakMinutes: 60),
        ]),
    ]

    /// Fixed ID of the "custom plan" (no template).
    public static let customID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!

    public static var defaultCustom: BreakPreset {
        BreakPreset(id: customID, name: "Custom plan", blocks: [
            PlanBlock(workMinutes: 75, breakMinutes: 15),
            PlanBlock(workMinutes: 60, breakMinutes: 10),
            PlanBlock(workMinutes: 50, breakMinutes: 60),
        ])
    }

    public var isCustom: Bool { id == Self.customID }
}

/// What the timer does when the Mac sleeps / the screen locks.
public enum SleepBehavior: String, Codable, Hashable, Sendable, CaseIterable {
    case pause
    case keepRunning
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var dailyGoalHours: Double = 6
    public var breaksEnabled: Bool = true
    public var presets: [BreakPreset] = BreakPreset.defaults
    /// The custom plan you edit freely, without a template (listed separately, can't be deleted).
    public var customPreset: BreakPreset = BreakPreset.defaultCustom
    public var activePresetID: UUID?
    public var snoozeMinutes: Int = 5
    public var idleDetectionEnabled: Bool = false
    public var idleMinutes: Int = 10
    public var sleepBehavior: SleepBehavior = .pause
    public var globalHotKeyEnabled: Bool = true
    public var autoBackupEnabled: Bool = true
    public var notificationsEnabled: Bool = true
    public var askNoteOnStop: Bool = true
    public var hasSeenWelcome: Bool = false

    public init() {
        activePresetID = presets.first(where: { $0.workMinutes == 50 })?.id
    }

    public var dailyGoalSeconds: TimeInterval { dailyGoalHours * 3600 }

    /// Saved templates + the custom plan.
    public var allPresets: [BreakPreset] { presets + [customPreset] }

    /// The selected break plan (falls back to the first template, then to 50/10).
    public var activePreset: BreakPreset {
        allPresets.first(where: { $0.id == activePresetID }) ?? presets.first
            ?? BreakPreset(name: "Classic", workMinutes: 50, breakMinutes: 10)
    }

    /// Updates or adds a template (including the custom plan) by its ID.
    public mutating func upsertPreset(_ p: BreakPreset) {
        if p.isCustom { customPreset = p; return }
        if let i = presets.firstIndex(where: { $0.id == p.id }) { presets[i] = p } else { presets.append(p) }
    }

    // Tolerant decoding, so JSON with old or missing fields still loads.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyGoalHours = try c.decodeIfPresent(Double.self, forKey: .dailyGoalHours) ?? dailyGoalHours
        breaksEnabled = try c.decodeIfPresent(Bool.self, forKey: .breaksEnabled) ?? breaksEnabled
        presets = try c.decodeIfPresent([BreakPreset].self, forKey: .presets) ?? presets
        customPreset = try c.decodeIfPresent(BreakPreset.self, forKey: .customPreset) ?? customPreset
        customPreset.id = BreakPreset.customID
        activePresetID = try c.decodeIfPresent(UUID.self, forKey: .activePresetID) ?? activePresetID
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? snoozeMinutes
        idleDetectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .idleDetectionEnabled) ?? idleDetectionEnabled
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? idleMinutes
        sleepBehavior = try c.decodeIfPresent(SleepBehavior.self, forKey: .sleepBehavior) ?? sleepBehavior
        globalHotKeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalHotKeyEnabled) ?? globalHotKeyEnabled
        autoBackupEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoBackupEnabled) ?? autoBackupEnabled
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? notificationsEnabled
        askNoteOnStop = try c.decodeIfPresent(Bool.self, forKey: .askNoteOnStop) ?? askNoteOnStop
        hasSeenWelcome = try c.decodeIfPresent(Bool.self, forKey: .hasSeenWelcome) ?? hasSeenWelcome
    }
}

// MARK: - Timer state (persisted)

public enum TimerPhase: String, Codable, Hashable, Sendable {
    case idle
    case working
    case paused
    case onBreak
}

/// Current timer state. Written to disk; the app continues from here after it reopens.
public struct RuntimeState: Codable, Hashable, Sendable {
    public var phase: TimerPhase = .idle
    public var sessionID: UUID?
    public var projectID: UUID?
    public var topicID: UUID?
    /// When the break ends (during a break).
    public var breakEndsAt: Date?
    /// (Field from an older version; unused now, kept so old files still decode.)
    public var nextBreakAtWork: TimeInterval?
    /// The break is over; waiting for the user to continue.
    public var awaitingResumeAfterBreak: Bool = false
    /// Paused by the system (sleep/lock).
    public var pausedBySystem: Bool = false
    /// The last moment the app was alive (for "end here" after a crash).
    public var lastHeartbeat: Date?
    /// The last day the goal celebration ran (start of day).
    public var lastCelebratedDay: Date?
    /// Day of the last automatic backup.
    public var lastAutoBackupDay: Date?

    // Daily plan progress
    /// The day the plan belongs to (on a new day the plan starts from the first block).
    public var planDay: Date?
    /// Which block of the day we are on (from 0).
    public var blockIndex: Int = 0
    /// This block's work is counted from this moment on (kept across sessions).
    public var blockStartedAt: Date?
    /// Seconds added to (or taken from) this block's work time by snoozing / quick adjustments.
    public var blockExtraSeconds: TimeInterval = 0
    /// Break length changed on the fly for this block (min).
    public var breakMinutesOverride: Int?

    public init() {}

    /// Tolerant decoding, so JSON written by older versions (without the new fields) still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decodeIfPresent(TimerPhase.self, forKey: .phase) ?? .idle
        sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID)
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        topicID = try c.decodeIfPresent(UUID.self, forKey: .topicID)
        breakEndsAt = try c.decodeIfPresent(Date.self, forKey: .breakEndsAt)
        nextBreakAtWork = try c.decodeIfPresent(TimeInterval.self, forKey: .nextBreakAtWork)
        awaitingResumeAfterBreak = try c.decodeIfPresent(Bool.self, forKey: .awaitingResumeAfterBreak) ?? false
        pausedBySystem = try c.decodeIfPresent(Bool.self, forKey: .pausedBySystem) ?? false
        lastHeartbeat = try c.decodeIfPresent(Date.self, forKey: .lastHeartbeat)
        lastCelebratedDay = try c.decodeIfPresent(Date.self, forKey: .lastCelebratedDay)
        lastAutoBackupDay = try c.decodeIfPresent(Date.self, forKey: .lastAutoBackupDay)
        planDay = try c.decodeIfPresent(Date.self, forKey: .planDay)
        blockIndex = try c.decodeIfPresent(Int.self, forKey: .blockIndex) ?? 0
        blockStartedAt = try c.decodeIfPresent(Date.self, forKey: .blockStartedAt)
        blockExtraSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .blockExtraSeconds) ?? 0
        breakMinutesOverride = try c.decodeIfPresent(Int.self, forKey: .breakMinutesOverride)
    }
}

// MARK: - All data

/// All data written to disk and exported / imported as JSON.
public struct AppData: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int = AppData.currentVersion
    public var projects: [Project] = []
    public var topics: [Topic] = []
    public var entries: [TimeEntry] = []
    public var notes: [Note] = []
    public var settings: AppSettings = AppSettings()
    public var runtime: RuntimeState = RuntimeState()

    public init() {}

    /// Missing fields get default values (old or hand-edited backups still load).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? AppData.currentVersion
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        topics = try c.decodeIfPresent([Topic].self, forKey: .topics) ?? []
        entries = try c.decodeIfPresent([TimeEntry].self, forKey: .entries) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        runtime = try c.decodeIfPresent(RuntimeState.self, forKey: .runtime) ?? RuntimeState()
    }
}
