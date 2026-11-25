import Foundation
import Testing
@testable import AthlosCore

@MainActor
@Suite("Widget bridge", .serialized)
struct WidgetSnapshotTests {
    @Test func commandsRoundTripThroughFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("athlos-widget-\(UUID().uuidString)")
        setenv("ATHLOS_DATA_DIR", dir.path, 1)
        defer { unsetenv("ATHLOS_DATA_DIR"); try? FileManager.default.removeItem(at: dir) }
        try WidgetCommand.toggle.send()
        try WidgetCommand.startBreak.send()
        #expect(WidgetCommand.drain() == [.toggle, .startBreak])
        #expect(WidgetCommand.drain().isEmpty) // okunan komutlar silinir
    }

    @Test func snapshotReflectsTimerState() throws {
        let f = Fixture()
        f.timer.start(projectID: f.project.id, topicID: f.topic.id)
        f.clock.advance(600)
        let snap = WidgetSnapshot.make(store: f.store, timer: f.timer, now: f.clock.now())
        #expect(snap.phase == .working)
        #expect(snap.title == "Disk setup")
        #expect(snap.sessionWork == 600)
        #expect(snap.sessionTimerStart == f.clock.now().addingTimeInterval(-600))
        #expect(snap.seconds(on: f.clock.now()) == 600)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("athlos-widget-\(UUID().uuidString)")
        setenv("ATHLOS_DATA_DIR", dir.path, 1)
        defer { unsetenv("ATHLOS_DATA_DIR"); try? FileManager.default.removeItem(at: dir) }
        try snap.save()
        #expect(WidgetSnapshot.load()?.title == "Disk setup")
    }
}
