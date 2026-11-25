import Foundation

/// Pure statistics functions (independent of the UI, testable).
public enum Stats {
    /// Total time in the given interval (entries outside it are clipped).
    public static func seconds(_ entries: some Sequence<TimeEntry>, kind: EntryKind = .work,
                               in interval: DateInterval? = nil, now: Date) -> TimeInterval {
        entries.reduce(0) { sum, e in
            guard e.kind == kind else { return sum }
            if let interval { return sum + e.duration(in: interval, now: now) }
            return sum + e.duration(now: now)
        }
    }

    /// Interval of a calendar day.
    public static func dayInterval(_ date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)!
    }

    /// Total per day (start of day → seconds). Entries crossing midnight are split across two days.
    public static func dailyTotals(_ entries: [TimeEntry], kind: EntryKind = .work, from start: Date, to end: Date,
                                   now: Date, calendar: Calendar = .current) -> [Date: TimeInterval] {
        var result: [Date: TimeInterval] = [:]
        let range = DateInterval(start: calendar.startOfDay(for: start), end: max(calendar.startOfDay(for: start), end))
        for e in entries where e.kind == kind {
            let eEnd = e.end ?? now
            guard eEnd > range.start, e.start < range.end else { continue }
            var cursor = max(e.start, range.start)
            let stop = min(eEnd, range.end)
            while cursor < stop {
                let day = calendar.startOfDay(for: cursor)
                let next = calendar.date(byAdding: .day, value: 1, to: day)!
                let segEnd = min(next, stop)
                result[day, default: 0] += segEnd.timeIntervalSince(cursor)
                cursor = segEnd
            }
        }
        return result
    }

    /// Number of days in a row the goal was met. If today isn't met yet, the streak counts from yesterday (it doesn't break).
    public static func streak(dailyTotals: [Date: TimeInterval], goal: TimeInterval, today: Date,
                              calendar: Calendar = .current) -> Int {
        guard goal > 0 else { return 0 }
        var day = calendar.startOfDay(for: today)
        if (dailyTotals[day] ?? 0) < goal {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while (dailyTotals[day] ?? 0) >= goal {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// Total of each topic + all its subtopics (rolled up the tree).
    /// - Returns: topicID → total seconds
    public static func rolledUpTopicTotals(topics: [Topic], direct: [UUID: TimeInterval]) -> [UUID: TimeInterval] {
        let byParent = Dictionary(grouping: topics, by: { $0.parentID })
        var memo: [UUID: TimeInterval] = [:]
        func total(_ id: UUID, depth: Int) -> TimeInterval {
            if let m = memo[id] { return m }
            guard depth < 10_000 else { return 0 } // guard against cycles
            let sum = (direct[id] ?? 0) + (byParent[id] ?? []).reduce(0) { $0 + total($1.id, depth: depth + 1) }
            memo[id] = sum
            return sum
        }
        for t in topics { _ = total(t.id, depth: 0) }
        return memo
    }

    /// Direct time per topic (subtopics not included).
    public static func directTopicTotals(_ entries: [TimeEntry], in interval: DateInterval? = nil, now: Date) -> [UUID: TimeInterval] {
        var result: [UUID: TimeInterval] = [:]
        for e in entries where e.kind == .work {
            guard let tid = e.topicID else { continue }
            result[tid, default: 0] += interval.map { e.duration(in: $0, now: now) } ?? e.duration(now: now)
        }
        return result
    }
}

// MARK: - AppStore helpers

public extension AppStore {
    /// Today's total work (breaks excluded).
    func todayWorkSeconds(now: Date, calendar: Calendar = .current) -> TimeInterval {
        Stats.seconds(entries, kind: .work, in: Stats.dayInterval(now, calendar: calendar), now: now)
    }

    func todayBreakSeconds(now: Date, calendar: Calendar = .current) -> TimeInterval {
        Stats.seconds(entries, kind: .breakTime, in: Stats.dayInterval(now, calendar: calendar), now: now)
    }

    /// Project total (all subtopics + past time entered by hand). With an `interval`, the manual time is not included.
    func projectSeconds(_ projectID: UUID, in interval: DateInterval? = nil, now: Date) -> TimeInterval {
        let tracked = Stats.seconds(entries.lazy.filter { $0.projectID == projectID }, kind: .work, in: interval, now: now)
        guard interval == nil else { return tracked }
        return tracked + (project(projectID)?.manualSeconds ?? 0)
    }

    /// Total of the topic itself + all its subtopics.
    func topicSeconds(_ topicID: UUID, in interval: DateInterval? = nil, now: Date) -> TimeInterval {
        let ids = descendantIDs(of: topicID).union([topicID])
        return Stats.seconds(entries.lazy.filter { $0.topicID.map(ids.contains) ?? false }, kind: .work, in: interval, now: now)
    }

    /// Rolled-up times for all topics of a project (in one pass; used by the tree view).
    func rolledUpTotals(projectID: UUID, in interval: DateInterval? = nil, now: Date) -> [UUID: TimeInterval] {
        let projectTopics = topics.filter { $0.projectID == projectID }
        let direct = Stats.directTopicTotals(entries.filter { $0.projectID == projectID }, in: interval, now: now)
        return Stats.rolledUpTopicTotals(topics: projectTopics, direct: direct)
    }

    func dailyWorkTotals(days: Int, now: Date, calendar: Calendar = .current) -> [Date: TimeInterval] {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        return Stats.dailyTotals(entries, from: start, to: Stats.dayInterval(now, calendar: calendar).end, now: now, calendar: calendar)
    }

    func currentStreak(now: Date, calendar: Calendar = .current) -> Int {
        let totals = dailyWorkTotals(days: 3650, now: now, calendar: calendar)
        return Stats.streak(dailyTotals: totals, goal: settings.dailyGoalSeconds, today: now, calendar: calendar)
    }
}

// MARK: - Day summary (the Today panel)

/// What happened on one day: work per project, sessions, breaks and a timeline. Pure and testable.
public struct DaySummary: Sendable, Equatable {
    /// One row of the day list: a session on one topic (pause/resume parts merged).
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var projectID: UUID
        public var topicID: UUID?
        public var start: Date
        /// nil while the session is still running.
        public var end: Date?
        public var seconds: TimeInterval
    }

    /// A piece of the timeline (clipped to the day).
    public struct Segment: Sendable, Equatable {
        public var start: Date
        public var end: Date
        public var kind: EntryKind
        public var projectID: UUID
    }

    /// Work per project, largest first.
    public var projects: [(id: UUID, seconds: TimeInterval)]
    public var workSeconds: TimeInterval
    public var breakSeconds: TimeInterval
    public var breakCount: Int
    /// Newest first.
    public var rows: [Row]
    /// In time order.
    public var segments: [Segment]

    public static func == (a: DaySummary, b: DaySummary) -> Bool {
        a.projects.map(\.id) == b.projects.map(\.id) && a.projects.map(\.seconds) == b.projects.map(\.seconds)
            && a.workSeconds == b.workSeconds && a.breakSeconds == b.breakSeconds && a.breakCount == b.breakCount
            && a.rows == b.rows && a.segments == b.segments
    }

    public static func make(_ entries: [TimeEntry], day: DateInterval, now: Date) -> DaySummary {
        let todays = entries.filter { $0.start < day.end && ($0.end ?? now) > day.start }.sorted { $0.start < $1.start }
        var perProject: [UUID: TimeInterval] = [:]
        var rowsByKey: [String: Row] = [:]
        var segments: [Segment] = []
        var breakSeconds: TimeInterval = 0
        var breakSessions = Set<String>()

        for e in todays {
            let secs = e.duration(in: day, now: now)
            let segEnd = min(e.end ?? now, day.end)
            let segStart = max(e.start, day.start)
            if segEnd > segStart {
                segments.append(Segment(start: segStart, end: segEnd, kind: e.kind, projectID: e.projectID))
            }
            if e.kind == .breakTime {
                breakSeconds += secs
                breakSessions.insert(e.id.uuidString)
                continue
            }
            perProject[e.projectID, default: 0] += secs
            let key = "\(e.sessionID?.uuidString ?? e.id.uuidString)|\(e.topicID?.uuidString ?? e.projectID.uuidString)"
            if var r = rowsByKey[key] {
                r.seconds += secs
                r.end = e.isRunning ? nil : max(r.end ?? e.end!, e.end!)
                rowsByKey[key] = r
            } else {
                rowsByKey[key] = Row(id: e.id, projectID: e.projectID, topicID: e.topicID, start: segStart,
                                     end: e.isRunning ? nil : segEnd, seconds: secs)
            }
        }
        let projects = perProject.filter { $0.value >= 1 }.map { (id: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
        return DaySummary(projects: projects,
                          workSeconds: perProject.values.reduce(0, +),
                          breakSeconds: breakSeconds,
                          breakCount: breakSessions.count,
                          rows: rowsByKey.values.filter { $0.seconds >= 1 }.sorted { $0.start > $1.start },
                          segments: segments)
    }
}
