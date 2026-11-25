import Foundation
import Testing
@testable import AthlosCore

@MainActor
@Suite("Tree operations")
struct TreeTests {
    @Test func nestedTotalsRollUp() {
        let f = Fixture()
        let raid = f.store.addTopic(name: "RAID setup", projectID: f.project.id, parentID: f.topic.id)!
        let deep = f.store.addTopic(name: "Parity", projectID: f.project.id, parentID: raid.id)!
        let t0 = f.clock.now()
        f.store.addManualEntry(projectID: f.project.id, topicID: deep.id, start: t0, end: t0 + 100)
        f.store.addManualEntry(projectID: f.project.id, topicID: raid.id, start: t0, end: t0 + 200)
        f.store.addManualEntry(projectID: f.project.id, topicID: f.topic.id, start: t0, end: t0 + 300)
        f.store.addManualEntry(projectID: f.project.id, topicID: nil, start: t0, end: t0 + 50)

        let now = t0 + 1000
        #expect(f.store.topicSeconds(deep.id, now: now) == 100)
        #expect(f.store.topicSeconds(raid.id, now: now) == 300)
        #expect(f.store.topicSeconds(f.topic.id, now: now) == 600)
        #expect(f.store.projectSeconds(f.project.id, now: now) == 650)

        let rolled = f.store.rolledUpTotals(projectID: f.project.id, now: now)
        #expect(rolled[f.topic.id] == 600)
        #expect(rolled[raid.id] == 300)
    }

    @Test func manualProjectSecondsAddToTotal() {
        let f = Fixture()
        var p = f.project
        p.manualSeconds = 19 * 3600
        f.store.updateProject(p)
        #expect(f.store.projectSeconds(p.id, now: f.clock.now()) == 19 * 3600)
    }

    @Test func deleteSubtreeKeepsEntriesOnParent() {
        let f = Fixture()
        let child = f.store.addTopic(name: "A", projectID: f.project.id, parentID: f.topic.id)!
        let grandchild = f.store.addTopic(name: "B", projectID: f.project.id, parentID: child.id)!
        let t0 = f.clock.now()
        f.store.addManualEntry(projectID: f.project.id, topicID: grandchild.id, start: t0, end: t0 + 60)
        f.store.addNote("not", projectID: f.project.id, topicID: grandchild.id)

        f.store.deleteTopic(child.id)
        #expect(f.store.topic(child.id) == nil)
        #expect(f.store.topic(grandchild.id) == nil)
        #expect(f.store.entries.first?.topicID == f.topic.id)
        #expect(f.store.notes.first?.topicID == f.topic.id)
        #expect(f.store.topicSeconds(f.topic.id, now: t0 + 100) == 60)
    }

    @Test func cannotMoveIntoOwnDescendant() {
        let f = Fixture()
        let child = f.store.addTopic(name: "A", projectID: f.project.id, parentID: f.topic.id)!
        #expect(f.store.moveTopic(f.topic.id, toProject: f.project.id, parent: child.id) == false)
        #expect(f.store.moveTopic(f.topic.id, toProject: f.project.id, parent: f.topic.id) == false)
        #expect(f.store.topic(f.topic.id)?.parentID == nil)
    }

    @Test func moveAcrossProjectsMovesSubtreeAndEntries() {
        let f = Fixture()
        let child = f.store.addTopic(name: "A", projectID: f.project.id, parentID: f.topic.id)!
        let other = f.store.addProject(name: "Kenshell")
        let t0 = f.clock.now()
        f.store.addManualEntry(projectID: f.project.id, topicID: child.id, start: t0, end: t0 + 120)

        #expect(f.store.moveTopic(f.topic.id, toProject: other.id, parent: nil))
        #expect(f.store.topic(f.topic.id)?.projectID == other.id)
        #expect(f.store.topic(child.id)?.projectID == other.id)
        #expect(f.store.projectSeconds(other.id, now: t0 + 200) == 120)
        #expect(f.store.projectSeconds(f.project.id, now: t0 + 200) == 0)
    }

    @Test func reorderSiblings() {
        let f = Fixture()
        let b = f.store.addTopic(name: "B", projectID: f.project.id)!
        let c = f.store.addTopic(name: "C", projectID: f.project.id)!
        #expect(f.store.children(projectID: f.project.id, parentID: nil).map(\.name) == ["Disk setup", "B", "C"])
        f.store.moveTopic(c.id, toProject: f.project.id, parent: nil, before: f.topic.id)
        #expect(f.store.children(projectID: f.project.id, parentID: nil).map(\.name) == ["C", "Disk setup", "B"])
        f.store.shiftTopic(c.id, by: 1)
        #expect(f.store.children(projectID: f.project.id, parentID: nil).map(\.name) == ["Disk setup", "C", "B"])
        f.store.shiftTopic(b.id, by: -2)
        #expect(f.store.children(projectID: f.project.id, parentID: nil).map(\.name) == ["B", "Disk setup", "C"])
    }

    @Test func pathString() {
        let f = Fixture()
        let raid = f.store.addTopic(name: "RAID setup", projectID: f.project.id, parentID: f.topic.id)!
        #expect(f.store.pathComponents(projectID: f.project.id, topicID: raid.id) == ["Server Storage", "Disk setup", "RAID setup"])
    }
}

@MainActor
@Suite("Statistics")
struct StatsTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }

    @Test func entrySpanningMidnightSplitsAcrossDays() {
        let cal = calendar
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 23))!
        let e = TimeEntry(projectID: UUID(), topicID: nil, start: day, end: day + 2 * 3600)
        let totals = Stats.dailyTotals([e], from: day - 86400, to: day + 86400 * 2, now: day + 99999, calendar: cal)
        #expect(totals[cal.startOfDay(for: day)] == 3600)
        #expect(totals[cal.startOfDay(for: day + 7200)] == 3600)
    }

    @Test func todayTotalExcludesBreaksAndOtherDays() {
        let f = Fixture()
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 15))!
        let yesterday = now - 86400
        f.store.addManualEntry(projectID: f.project.id, topicID: nil, start: now - 7200, end: now - 3600)
        f.store.addManualEntry(projectID: f.project.id, topicID: nil, kind: .breakTime, start: now - 3600, end: now - 3000)
        f.store.addManualEntry(projectID: f.project.id, topicID: nil, start: yesterday, end: yesterday + 3600)
        #expect(f.store.todayWorkSeconds(now: now, calendar: cal) == 3600)
        #expect(f.store.todayBreakSeconds(now: now, calendar: cal) == 600)
    }

    @Test func streakCountsConsecutiveGoalDays() {
        let cal = calendar
        let today = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!)
        let goal: TimeInterval = 6 * 3600
        func d(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
        var totals: [Date: TimeInterval] = [d(-1): goal, d(-2): goal + 10, d(-3): goal, d(-4): 100, d(-5): goal]
        // Today not met yet → 3 days counted from yesterday.
        #expect(Stats.streak(dailyTotals: totals, goal: goal, today: today, calendar: cal) == 3)
        totals[today] = goal
        #expect(Stats.streak(dailyTotals: totals, goal: goal, today: today, calendar: cal) == 4)
    }
}

@MainActor
@Suite("Yedekleme")
struct BackupTests {
    @Test func roundTripPreservesData() throws {
        let f = Fixture()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000.123)
        f.store.addManualEntry(projectID: f.project.id, topicID: f.topic.id, start: t0, end: t0 + 61.5)
        f.store.addNote("hello", projectID: f.project.id, topicID: f.topic.id)
        let raw = try BackupService.encode(BackupService.makeBackup(store: f.store, includeImages: false))
        let decoded = try BackupService.decode(raw)
        let other = AppStore()
        BackupService.restore(decoded, into: other)
        // Dates are stored in JSON with millisecond precision.
        #expect(other.projects.map(\.id) == f.store.projects.map(\.id))
        #expect(other.topics.map(\.name) == f.store.topics.map(\.name))
        #expect(other.entries.map(\.id) == f.store.entries.map(\.id))
        let a = other.entries[0], b = f.store.entries[0]
        #expect(abs(a.start.timeIntervalSince(b.start)) < 0.001)
        #expect(abs(a.duration(now: .now) - 61.5) < 0.001)
        #expect(other.notes.first?.text == "hello")
    }

    @Test func autoBackupKeepsLastSeven() throws {
        let f = Fixture()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("athlos-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for day in 0..<10 {
            let url = BackupService.autoBackupIfNeeded(store: f.store, directory: dir, now: base + Double(day) * 86400)
            #expect(url != nil)
        }
        // No second backup on the same day.
        #expect(BackupService.autoBackupIfNeeded(store: f.store, directory: dir, now: base + 9 * 86400 + 60) == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.count == 7)
    }

    @Test func persistenceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("athlos-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(persistence: JSONFilePersistence(url: url))
        let p = store.addProject(name: "Kenshell", icon: .emoji("🐚"), manualSeconds: 19 * 3600, status: .completed)
        let reloaded = AppStore(persistence: JSONFilePersistence(url: url))
        #expect(reloaded.projects.map(\.id) == [p.id])
        #expect(reloaded.projects.first?.icon == .emoji("🐚"))
        #expect(reloaded.projects.first?.manualSeconds == TimeInterval(19 * 3600))
        #expect(reloaded.projects.first?.status == .completed)
    }
}
