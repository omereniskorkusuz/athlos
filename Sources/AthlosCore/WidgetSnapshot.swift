import Foundation

/// Data shared between Athlos and its macOS widgets.
/// - The app writes this snapshot to `~/Library/Application Support/Athlos/widget-snapshot.json`.
/// - The sandboxed widget extension reads the same file with a read-only exception.
/// - Widget buttons drop a command file into `WidgetCommands/` and post a Darwin notification;
/// the app applies the command and refreshes the snapshot.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var goalSeconds: TimeInterval
    /// "yyyy-MM-dd" → work on that day (seconds); last ~70 days.
    public var dailyTotals: [String: TimeInterval]
    public var todayWork: TimeInterval
    public var phase: TimerPhase
    /// Last component and full path of the active topic.
    public var title: String?
    public var path: String?
    public var colorHex: String?
    /// Session work at `generatedAt` (the live timer is derived from it).
    public var sessionWork: TimeInterval
    public var breakEndsAt: Date?
    public var workUntilBreak: TimeInterval?
    public var blockLabel: String?
    public var planName: String?
    public var breaksEnabled: Bool
    public var hasRecent: Bool

    public init(generatedAt: Date, goalSeconds: TimeInterval, dailyTotals: [String: TimeInterval], todayWork: TimeInterval,
                phase: TimerPhase, title: String?, path: String?, colorHex: String?, sessionWork: TimeInterval,
                breakEndsAt: Date?, workUntilBreak: TimeInterval?, blockLabel: String?, planName: String?,
                breaksEnabled: Bool, hasRecent: Bool) {
        self.generatedAt = generatedAt
        self.goalSeconds = goalSeconds
        self.dailyTotals = dailyTotals
        self.todayWork = todayWork
        self.phase = phase
        self.title = title
        self.path = path
        self.colorHex = colorHex
        self.sessionWork = sessionWork
        self.breakEndsAt = breakEndsAt
        self.workUntilBreak = workUntilBreak
        self.blockLabel = blockLabel
        self.planName = planName
        self.breaksEnabled = breaksEnabled
        self.hasRecent = hasRecent
    }

    /// Empty snapshot used for previews / when there is no data.
    public static var empty: WidgetSnapshot {
        WidgetSnapshot(generatedAt: Date(), goalSeconds: 6 * 3600, dailyTotals: [:], todayWork: 0, phase: .idle,
                       title: nil, path: nil, colorHex: nil, sessionWork: 0, breakEndsAt: nil, workUntilBreak: nil,
                       blockLabel: nil, planName: nil, breaksEnabled: false, hasRecent: false)
    }

    // MARK: Day key

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func seconds(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        dailyTotals[Self.dayKey(day, calendar: calendar)] ?? 0
    }

    // MARK: Live values (the widget runs the clock itself)

    /// While working: the timer is shown as if it started at this moment (`Text(date, style: .timer)`).
    public var sessionTimerStart: Date { generatedAt.addingTimeInterval(-sessionWork) }
    /// Same trick for today's total while working.
    public var todayTimerStart: Date { generatedAt.addingTimeInterval(-todayWork) }

    // MARK: File locations

    /// The real home folder (also inside the sandbox, where `NSHomeDirectory()` returns the container).
    public static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["ATHLOS_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return realHome.appendingPathComponent("Library/Application Support/Athlos", isDirectory: true)
    }

    public static var fileURL: URL { directory.appendingPathComponent("widget-snapshot.json") }
    public static var commandsDirectory: URL { directory.appendingPathComponent("WidgetCommands", isDirectory: true) }

    /// Widget → app signal (Darwin notification).
    public static let commandNotification = "app.athlos.widget.command"
    /// Widget kinds (for WidgetCenter reloads).
    public static let heatmapKind = "AthlosHeatmap"
    public static let timerKind = "AthlosTimer"

    public static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? AthlosJSON.decoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try AthlosJSON.encoder().encode(self).write(to: Self.fileURL, options: .atomic)
    }
}

/// Commands that widget buttons send to the app.
public enum WidgetCommand: String, Codable, Sendable, CaseIterable {
    case toggle, stop, startBreak, skipBreak

    /// Drops the command as a file and posts a Darwin notification to the app (widget side).
    public func send() throws {
        let dir = WidgetSnapshot.commandsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // "<ms>-<system uptime ns, zero-padded>-<random>.<command>": the uptime part keeps two commands sent in the
        // same millisecond in order (it is system-wide, so it also orders the widget's and the app's commands).
        let uptime = String(format: "%020llu", DispatchTime.now().uptimeNanoseconds)
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(uptime)-\(UUID().uuidString.prefix(6)).\(rawValue)"
        try Data(rawValue.utf8).write(to: dir.appendingPathComponent(name), options: .atomic)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(WidgetSnapshot.commandNotification as CFString),
                                             nil, nil, true)
    }

    /// Reads and deletes pending commands (app side). Commands older than 2 minutes are ignored.
    public static func drain(now: Date = Date()) -> [WidgetCommand] {
        let dir = WidgetSnapshot.commandsDirectory
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [WidgetCommand] = []
        for f in files {
            defer { try? FileManager.default.removeItem(at: f) }
            let parts = f.lastPathComponent.split(separator: "-")
            if let ms = parts.first.flatMap({ Double($0) }), now.timeIntervalSince1970 * 1000 - ms > 120_000 { continue }
            if let cmd = WidgetCommand(rawValue: f.pathExtension) { result.append(cmd) }
        }
        return result
    }
}

// MARK: - Building the snapshot (app side)

public extension WidgetSnapshot {
    @MainActor
    static func make(store: AppStore, timer: TimerService, now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let totals = store.dailyWorkTotals(days: 70, now: now, calendar: calendar)
        var keyed: [String: TimeInterval] = [:]
        for (day, secs) in totals where secs > 0 { keyed[dayKey(day, calendar: calendar)] = secs }
        let rt = store.runtime
        let parts = store.pathComponents(projectID: rt.projectID, topicID: rt.topicID)
        let preset = store.settings.activePreset
        return WidgetSnapshot(
            generatedAt: now,
            goalSeconds: store.settings.dailyGoalSeconds,
            dailyTotals: keyed,
            todayWork: store.todayWorkSeconds(now: now, calendar: calendar),
            phase: rt.phase,
            title: parts.last,
            path: parts.isEmpty ? nil : parts.joined(separator: " › "),
            colorHex: store.project(rt.projectID)?.colorHex,
            sessionWork: timer.sessionWorkSeconds(now: now),
            breakEndsAt: rt.phase == .onBreak ? rt.breakEndsAt : nil,
            workUntilBreak: timer.workUntilBreak(now: now),
            // Only numbers here ("2 · 60/10"); the widget adds the localized "Block" word.
            blockLabel: store.settings.breaksEnabled ? "\(timer.currentBlockNumber) · \(Int(timer.currentBlockWorkTarget / 60))/\(timer.currentBlockBreakMinutes)" : nil,
            planName: preset.isCustom ? "Custom plan" : preset.name,
            breaksEnabled: store.settings.breaksEnabled,
            hasRecent: !store.recentTargets(limit: 1).isEmpty
        )
    }

    /// Compares without fields that don't change the widget's look (avoids needless writes/reloads).
    func isVisuallyEqual(to o: WidgetSnapshot) -> Bool {
        phase == o.phase && title == o.title && path == o.path && colorHex == o.colorHex
            && breakEndsAt == o.breakEndsAt && blockLabel == o.blockLabel && planName == o.planName
            && breaksEnabled == o.breaksEnabled && goalSeconds == o.goalSeconds
            // The live timer runs on its own in the widget; a 10-minute change is enough for the heatmap.
            && Int(todayWork / 600) == Int(o.todayWork / 600) && dailyTotals.keys == o.dailyTotals.keys
            && abs(sessionTimerStart.timeIntervalSince(o.sessionTimerStart)) < 2
    }
}
