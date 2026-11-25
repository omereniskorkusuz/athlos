import Foundation
import Testing
@testable import AthlosCore

/// Shared test setup: in-memory store + a clock moved by hand.
@MainActor
struct Fixture {
    let clock: ManualTimeSource
    let store: AppStore
    let timer: TimerService
    let project: Project
    let topic: Topic

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        clock = ManualTimeSource(start)
        store = AppStore()
        timer = TimerService(store: store, clock: clock)
        project = store.addProject(name: "Server Storage")
        topic = store.addTopic(name: "Disk setup", projectID: project.id)!
    }
}

@MainActor
@Suite("Timer and durations")
struct TimerServiceTests {
    @Test func durationIsComputedFromTimestamps() {
        let f = Fixture()
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(3600)
        // tick() was never called; the duration is still correct.
        #expect(f.timer.sessionWorkSeconds() == 3600)
        #expect(f.store.todayWorkSeconds(now: f.clock.now()) == 3600)
    }

    @Test func pauseResumeExcludesPausedTime() {
        let f = Fixture()
        f.store.updateSettings { $0.breaksEnabled = false }
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(600)
        f.timer.pause()
        f.clock.advance(900) // paused time
        f.timer.resume()
        f.clock.advance(300)
        #expect(f.timer.sessionWorkSeconds() == 900)
        f.timer.stop(note: "RAID configured")
        #expect(f.timer.phase == .idle)
        #expect(f.store.entries.count == 2)
        #expect(f.store.entries.allSatisfy { !$0.isRunning })
        #expect(f.store.notes.first?.text == "RAID configured")
        #expect(f.store.notes.first?.topicID == f.topic.id)
    }

    @Test func toggleWithoutTopicReturnsFalse() {
        let f = Fixture()
        #expect(f.timer.toggle() == false)
        f.timer.start(projectID: f.project.id, topicID: nil)
        #expect(f.timer.toggle() == true)
        #expect(f.timer.phase == .paused)
    }

    @Test func autoBreakStartsAndEndsAndIsNotCountedAsWork() {
        let f = Fixture()
        f.store.updateSettings {
            $0.presets = [BreakPreset(name: "Test", workMinutes: 50, breakMinutes: 10)]
            $0.activePresetID = $0.presets[0].id
        }
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(49 * 60)
        #expect(f.timer.tick().isEmpty)
        f.clock.advance(60)
        let events = f.timer.tick()
        #expect(events.count == 1)
        #expect(f.timer.phase == .onBreak)

        // Work time doesn't grow during a break.
        f.clock.advance(5 * 60)
        #expect(f.timer.sessionWorkSeconds() == 50 * 60)
        #expect(f.timer.breakRemaining() == 5 * 60)

        // Even if the tick comes 3 min late, exactly 10 min of break is recorded.
        f.clock.advance(8 * 60)
        #expect(f.timer.tick() == [.breakEnded])
        #expect(f.timer.phase == .paused)
        #expect(f.store.runtime.awaitingResumeAfterBreak)
        #expect(f.timer.sessionBreakSeconds() == 10 * 60)
        #expect(f.store.todayBreakSeconds(now: f.clock.now()) == 10 * 60)

        // Continue → the next break comes 50 min later.
        f.timer.resume()
        f.clock.advance(50 * 60 - 1)
        #expect(f.timer.tick().isEmpty)
        f.clock.advance(1)
        #expect(f.timer.tick().count == 1)
    }

    @Test func manualBreakAndResume() {
        let f = Fixture()
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(1200)
        f.timer.startBreak()
        #expect(f.timer.phase == .onBreak)
        f.clock.advance(120)
        f.timer.resume() // break ended early
        #expect(f.timer.phase == .working)
        #expect(f.timer.sessionBreakSeconds() == 120)
        f.clock.advance(60)
        #expect(f.timer.sessionWorkSeconds() == 1260)
    }

    @Test func snoozeAndSkipBreak() {
        let f = Fixture()
        f.store.updateSettings {
            $0.presets = [BreakPreset(name: "P", workMinutes: 25, breakMinutes: 5)]
            $0.activePresetID = $0.presets[0].id
            $0.snoozeMinutes = 5
        }
        f.timer.start(projectID: f.project.id, topicID: nil)
        f.clock.advance(25 * 60)
        f.timer.tick()
        #expect(f.timer.phase == .onBreak)
        f.timer.snoozeBreak()
        #expect(f.timer.phase == .working)
        #expect(f.timer.sessionBreakSeconds() == 0) // the unused break was deleted
        f.clock.advance(5 * 60)
        f.timer.tick()
        #expect(f.timer.phase == .onBreak)
        f.timer.skipBreak()
        #expect(f.timer.phase == .working)
        #expect(abs((f.timer.workUntilBreak() ?? 0) - 25 * 60) < 0.001)
    }

    @Test func sleepWithPauseSettingStopsCountingAtSleepTime() {
        let f = Fixture()
        f.store.updateSettings { $0.sleepBehavior = .pause; $0.breaksEnabled = false }
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(1800)
        f.timer.systemWillSleep()
        f.clock.advance(4 * 3600) // the Mac slept for 4 hours
        f.timer.systemDidWake()
        #expect(f.timer.phase == .paused)
        #expect(f.store.runtime.pausedBySystem)
        #expect(f.timer.sessionWorkSeconds() == 1800)
        f.timer.resume()
        f.clock.advance(600)
        #expect(f.timer.sessionWorkSeconds() == 2400)
    }

    @Test func sleepWithKeepRunningCountsSleepAndTriggersBreakOnWake() {
        let f = Fixture()
        f.store.updateSettings { $0.sleepBehavior = .keepRunning }
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.timer.systemWillSleep()
        f.clock.advance(3 * 3600)
        #expect(f.timer.phase == .working)
        #expect(f.timer.sessionWorkSeconds() == 3 * 3600)
        // On wake the break threshold has been passed, so a break starts.
        #expect(f.timer.systemDidWake().count == 1)
    }

    @Test func recoveryAfterCrash() {
        let f = Fixture()
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(600)
        f.timer.heartbeat()
        let aliveAt = f.clock.now()

        // "Crash": a new service is created from the same data and reopened 2 hours later.
        let reopened = TimerService(store: f.store, clock: f.clock)
        f.clock.advance(7200)
        let info = reopened.pendingRecovery()
        #expect(info?.lastAlive == aliveAt)
        reopened.recoverFinish(at: aliveAt)
        #expect(reopened.phase == .idle)
        #expect(f.store.entries.first?.duration(now: f.clock.now()) == 600)
        #expect(reopened.pendingRecovery() == nil)
    }

    @Test func recoveryContinueKeepsCounting() {
        let f = Fixture()
        f.store.updateSettings { $0.breaksEnabled = false }
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(600)
        let reopened = TimerService(store: f.store, clock: f.clock)
        f.clock.advance(600)
        reopened.recoverContinue()
        #expect(reopened.phase == .working)
        #expect(reopened.sessionWorkSeconds() == 1200)
    }

    @Test func discardIdleRemovesIdleTime() {
        let f = Fixture()
        f.store.updateSettings { $0.breaksEnabled = false }
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(1000)
        let idleStart = f.clock.now()
        f.clock.advance(900)
        f.timer.discardIdle(since: idleStart)
        #expect(f.timer.sessionWorkSeconds() == 1000)
        f.clock.advance(100)
        #expect(f.timer.sessionWorkSeconds() == 1100)
        #expect(f.timer.phase == .working)
    }

    @Test func zeroLengthEntriesAreDropped() {
        let f = Fixture()
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.timer.pause() // at the same moment: 0 s
        #expect(f.store.entries.isEmpty)
        f.timer.resume()
        f.clock.advance(5)
        f.timer.stop()
        #expect(f.store.entries.count == 1)
    }

    @Test func overlapDetection() {
        let f = Fixture()
        let t0 = f.clock.now()
        let a = f.store.addManualEntry(projectID: f.project.id, topicID: nil, start: t0, end: t0 + 3600)!
        f.store.addManualEntry(projectID: f.project.id, topicID: nil, kind: .breakTime, start: t0, end: t0 + 600)
        #expect(f.store.overlappingEntries(start: t0 + 1800, end: t0 + 5400).map(\.id) == [a.id])
        #expect(f.store.overlappingEntries(start: t0 + 3600, end: t0 + 5400).isEmpty) // end to end: no overlap
        #expect(f.store.overlappingEntries(start: t0, end: t0 + 60, excluding: a.id).isEmpty)
    }

    @Test func switchingTargetKeepsSession() {
        let f = Fixture()
        let other = f.store.addTopic(name: "RAID", projectID: f.project.id, parentID: f.topic.id)!
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(100)
        f.timer.switchTarget(projectID: f.project.id, topicID: other.id)
        f.clock.advance(50)
        #expect(f.timer.sessionWorkSeconds() == 150)
        #expect(f.store.topicSeconds(other.id, now: f.clock.now()) == 50)
        #expect(f.store.topicSeconds(f.topic.id, now: f.clock.now()) == 150) // rolls up to the parent topic
    }
}
