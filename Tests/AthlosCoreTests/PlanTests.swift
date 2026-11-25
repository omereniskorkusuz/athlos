import Foundation
import Testing
@testable import AthlosCore

/// Tests for the daily plan (a series of blocks), e.g. 75/15 → 60/10 → 50/60.
@MainActor
@Suite("Daily break plan")
struct PlanTests {
    /// Fixture whose clock is set to a fixed morning (no day-boundary surprises).
    func makeFixture(blocks: [(Int, Int)], afterLast: PlanRepeat = .repeatLast) -> Fixture {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let morning = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 9))!
        let f = Fixture(start: morning)
        f.timer.calendar = cal
        let plan = BreakPreset(name: "My workday", blocks: blocks.map { PlanBlock(workMinutes: $0.0, breakMinutes: $0.1) },
                               afterLast: afterLast)
        f.store.updateSettings {
            $0.presets = [plan]
            $0.activePresetID = plan.id
            $0.breaksEnabled = true
        }
        return f
    }

    /// Work → break starts → break ends → continue.
    func runBlock(_ f: Fixture, work: Int, expectBreak: Int) {
        f.clock.advance(TimeInterval(work * 60 - 1))
        #expect(f.timer.tick().isEmpty, "Break started too early")
        f.clock.advance(1)
        let events = f.timer.tick()
        #expect(events.count == 1, "Break did not start at minute \(work)")
        #expect(f.timer.phase == .onBreak)
        #expect(abs(f.timer.breakRemaining() - TimeInterval(expectBreak * 60)) < 0.001)
        f.clock.advance(TimeInterval(expectBreak * 60))
        #expect(f.timer.tick() == [.breakEnded])
        f.timer.resume()
    }

    @Test func blocksAreAppliedInOrder() {
        let f = makeFixture(blocks: [(75, 15), (60, 10), (50, 60)])
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        #expect(f.timer.currentBlockNumber == 1)
        runBlock(f, work: 75, expectBreak: 15)
        #expect(f.timer.currentBlockNumber == 2)
        runBlock(f, work: 60, expectBreak: 10)
        runBlock(f, work: 50, expectBreak: 60)
        // After the last block: the last block repeats
        runBlock(f, work: 50, expectBreak: 60)
        // Breaks don't count as work
        #expect(abs(f.store.todayWorkSeconds(now: f.clock.now(), calendar: f.timer.calendar) - TimeInterval((75 + 60 + 50 + 50) * 60)) < 0.001)
        #expect(abs(f.store.todayBreakSeconds(now: f.clock.now(), calendar: f.timer.calendar) - TimeInterval((15 + 10 + 60 + 60) * 60)) < 0.001)
    }

    @Test func cyclePlanStartsOver() {
        let f = makeFixture(blocks: [(30, 5), (20, 10)], afterLast: .cycle)
        f.timer.start(projectID: f.project.id, topicID: nil)
        runBlock(f, work: 30, expectBreak: 5)
        runBlock(f, work: 20, expectBreak: 10)
        runBlock(f, work: 30, expectBreak: 5)
    }

    @Test func blockContinuesAcrossSessionsSameDay() {
        let f = makeFixture(blocks: [(75, 15), (60, 10)])
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(30 * 60)
        f.timer.stop()
        f.clock.advance(2 * 3600) // lunch break: not counted
        f.timer.start(projectID: f.project.id, topicID: nil)
        #expect(abs((f.timer.workUntilBreak() ?? 0) - 45 * 60) < 0.001)
        f.clock.advance(45 * 60)
        #expect(f.timer.tick().count == 1)
    }

    @Test func newDayRestartsPlan() {
        let f = makeFixture(blocks: [(75, 15), (60, 10)])
        f.timer.start(projectID: f.project.id, topicID: nil)
        runBlock(f, work: 75, expectBreak: 15)
        #expect(f.timer.currentBlockNumber == 2)
        f.timer.stop()
        f.clock.advance(20 * 3600) // the next day
        f.timer.start(projectID: f.project.id, topicID: nil)
        #expect(f.timer.currentBlockNumber == 1)
        #expect(abs((f.timer.workUntilBreak() ?? 0) - 75 * 60) < 0.001)
    }

    @Test func adjustCurrentBlockOnTheFly() {
        let f = makeFixture(blocks: [(50, 10)])
        f.timer.start(projectID: f.project.id, topicID: nil)
        f.clock.advance(20 * 60)
        f.timer.setCurrentBlockWorkMinutes(75) // make this block 75 min
        f.timer.setCurrentBlockBreakMinutes(15)
        #expect(abs((f.timer.workUntilBreak() ?? 0) - 55 * 60) < 0.001)
        f.clock.advance(55 * 60)
        #expect(f.timer.tick().count == 1)
        #expect(abs(f.timer.breakRemaining() - 15 * 60) < 0.001)
        // The length can be changed during a break too
        f.timer.setCurrentBlockBreakMinutes(5)
        #expect(abs(f.timer.breakRemaining() - 5 * 60) < 0.001)
        f.clock.advance(5 * 60)
        f.timer.tick()
        f.timer.resume()
        // The quick adjustment belonged to that block only; the next block uses the template again
        #expect(abs((f.timer.workUntilBreak() ?? 0) - 50 * 60) < 0.001)
    }

    @Test func legacyPresetAndRuntimeDecode() throws {
        // Settings/runtime format written by the previous version
        let json = """
        {"settings":{"activePresetID":"EEE30987-A2A8-4DD7-A383-C47F8B61E6C9","breaksEnabled":false,
          "presets":[{"breakMinutes":10,"id":"EEE30987-A2A8-4DD7-A383-C47F8B61E6C9","name":"kens","workMinutes":45}]},
         "runtime":{"phase":"working","nextBreakAtWork":3000,"awaitingResumeAfterBreak":false,"pausedBySystem":false}}
        """
        let d = try AthlosJSON.decoder().decode(AppData.self, from: Data(json.utf8))
        #expect(d.settings.presets.count == 1)
        #expect(d.settings.activePreset.name == "kens")
        #expect(d.settings.activePreset.blocks == [PlanBlock(id: d.settings.activePreset.blocks[0].id, workMinutes: 45, breakMinutes: 10)])
        #expect(d.settings.customPreset.isCustom)
        #expect(d.runtime.phase == .working)
        #expect(d.runtime.blockIndex == 0)
        // Must be writable in the new format and readable again
        let again = try AthlosJSON.decoder().decode(AppData.self, from: AthlosJSON.encoder().encode(d))
        #expect(again.settings.activePreset.summary == "45/10")
    }

    @Test func appearanceSettingDecodesAndRoundTrips() throws {
        // Old data has no "appearance" key → follows the system.
        let old = try AthlosJSON.decoder().decode(AppData.self, from: Data(#"{"settings":{"dailyGoalHours":5}}"#.utf8))
        #expect(old.settings.appearance == .system)
        #expect(old.settings.dailyGoalHours == 5)
        // An unknown value (e.g. from a newer version) must not break loading.
        let unknown = try AthlosJSON.decoder().decode(AppData.self, from: Data(#"{"settings":{"appearance":"sepia"}}"#.utf8))
        #expect(unknown.settings.appearance == .system)
        var d = old
        d.settings.appearance = .dark
        let again = try AthlosJSON.decoder().decode(AppData.self, from: AthlosJSON.encoder().encode(d))
        #expect(again.settings.appearance == .dark)
    }

    @Test func customPlanIsSelectable() {
        let f = makeFixture(blocks: [(50, 10)])
        var custom = f.store.settings.customPreset
        custom.blocks = [PlanBlock(workMinutes: 40, breakMinutes: 8)]
        f.store.updateSettings {
            $0.upsertPreset(custom)
            $0.activePresetID = BreakPreset.customID
        }
        #expect(f.store.settings.activePreset.summary == "40/8")
        f.timer.start(projectID: f.project.id, topicID: nil)
        runBlock(f, work: 40, expectBreak: 8)
    }
}

/// Optional: with ATHLOS_COMPAT_FILE=/path/data.json, checks that a real data
/// file still loads with the new version (otherwise the test is skipped).
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["ATHLOS_COMPAT_FILE"] != nil))
func realDataFileStillLoads() throws {
    let path = ProcessInfo.processInfo.environment["ATHLOS_COMPAT_FILE"]!
    let store = AppStore(persistence: JSONFilePersistence(url: URL(fileURLWithPath: path)))
    #expect(store.lastSaveError == nil)
    #expect(!store.settings.presets.isEmpty)
    print("COMPAT: \(store.projects.count) projects, \(store.entries.count) entries, templates: \(store.settings.allPresets.map { "\($0.name)=\($0.summary)" })")
}
