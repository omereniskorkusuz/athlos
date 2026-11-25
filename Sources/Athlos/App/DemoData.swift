import Foundation
import AthlosCore

/// Only with `ATHLOS_DEMO=1` and empty data: creates sample data for trying out the screens.
@MainActor
enum DemoData {
    static func seedIfRequested(_ store: AppStore) {
        guard ProcessInfo.processInfo.environment["ATHLOS_DEMO"] == "1", store.projects.isEmpty else { return }
        let cal = Calendar.current
        let now = Date()

        let storage = store.addProject(name: "Server Storage", icon: .symbol("server.rack"), colorHex: "#A84B24",
                                       createdAt: cal.date(byAdding: .day, value: -60, to: now)!)
        let disk = store.addTopic(name: "Disk setup", projectID: storage.id)!
        let raid = store.addTopic(name: "RAID setup", projectID: storage.id, parentID: disk.id)!
        let nfs = store.addTopic(name: "NFS share", projectID: storage.id)!
        let web = store.addProject(name: "Portfolio Website", icon: .emoji("🌐"), colorHex: "#4E7C8A",
                                   createdAt: cal.date(byAdding: .day, value: -40, to: now)!)
        let ui = store.addTopic(name: "Interface", projectID: web.id)!
        let seo = store.addTopic(name: "SEO", projectID: web.id)!

        var kenshell = store.addProject(name: "Kenshell", icon: .symbol("terminal.fill"), colorHex: "#3F3F46",
                                        manualSeconds: 19 * 3600, status: .completed,
                                        createdAt: cal.date(byAdding: .day, value: -200, to: now)!)
        kenshell.completedAt = cal.date(byAdding: .day, value: -150, to: now)
        store.updateProject(kenshell)
        var tez = store.addProject(name: "Thesis", icon: .emoji("🎓"), colorHex: "#8A6A4F",
                                   manualSeconds: 121 * 3600, status: .completed,
                                   createdAt: cal.date(byAdding: .day, value: -400, to: now)!)
        tez.completedAt = cal.date(byAdding: .day, value: -250, to: now)
        store.updateProject(tez)

        let targets: [(UUID, UUID?)] = [(storage.id, raid.id), (storage.id, disk.id), (storage.id, nfs.id), (web.id, ui.id), (web.id, seo.id), (web.id, nil)]
        var rng = SystemRandomNumberGenerator()
        for dayOffset in stride(from: -120, through: -1, by: 1) {
            guard Int.random(in: 0..<10, using: &rng) < 7 else { continue }
            let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now))!
            var cursor = cal.date(bySettingHour: 9, minute: Int.random(in: 0..<50), second: 0, of: day)!
            for _ in 0..<Int.random(in: 2...6, using: &rng) {
                let t = targets.randomElement(using: &rng)!
                let len = TimeInterval(Int.random(in: 30...95, using: &rng) * 60)
                store.addManualEntry(projectID: t.0, topicID: t.1, start: cursor, end: cursor + len)
                cursor += len
                store.addManualEntry(projectID: t.0, topicID: t.1, kind: .breakTime, start: cursor, end: cursor + 600)
                cursor += 600 + TimeInterval(Int.random(in: 0...40) * 60)
            }
        }
        // Today ~5 hours (close to the goal)
        let morning = cal.date(bySettingHour: 8, minute: 30, second: 0, of: now)!
        store.addManualEntry(projectID: storage.id, topicID: raid.id, start: morning, end: morning + 3 * 3600)
        store.addManualEntry(projectID: web.id, topicID: ui.id, start: morning + 3.3 * 3600, end: morning + 5.2 * 3600)
        store.addNote("Chose RAID 10, 4×4 TB.", projectID: storage.id, topicID: raid.id)
        store.addNote("Review the NFS export settings.", projectID: storage.id, topicID: nfs.id)
        store.addNote("Command history and autocomplete are done.", projectID: kenshell.id, topicID: nil)
    }

    /// Demo mode only: open the project tree fully and select a sample subtopic (used for README screenshots).
    static func prepareUI(_ model: AppModel) {
        guard ProcessInfo.processInfo.environment["ATHLOS_DEMO"] == "1" else { return }
        model.expandedNodes = Set(model.store.projects.map(\.id) + model.store.topics.map(\.id))
        if let raid = model.store.topics.first(where: { $0.name == "RAID setup" }) {
            model.treeSelection = .topic(raid.id)
            // ATHLOS_DEMO_START=1: a running session on RAID setup (for Timer screenshots).
            if env["ATHLOS_DEMO_START"] == "1", model.timer.phase == .idle {
                model.start(projectID: raid.projectID, topicID: raid.id)
            }
        }
        // ATHLOS_DEMO_ROUTE=timer|projects|stats|showcase|settings opens that page.
        if let r = env["ATHLOS_DEMO_ROUTE"].flatMap(Route.init(rawValue:)) { model.route = r }
        // ATHLOS_DEMO_SHEET=plan opens the editor of the "Daily flow" template.
        if env["ATHLOS_DEMO_SHEET"] == "plan",
           let flow = model.store.settings.presets.first(where: { $0.blocks.count > 1 }) {
            model.planEditor = PlanEditorRequest(presetID: flow.id)
        }
        // ATHLOS_DEMO_PANEL=1 shows the desktop panel.
        if env["ATHLOS_DEMO_PANEL"] == "1" { DispatchQueue.main.async { model.setDesktopWidget(visible: true) } }
        // ATHLOS_DEMO_APPEARANCE=light|dark forces the theme for this run.
        if let a = env["ATHLOS_DEMO_APPEARANCE"].flatMap(AppearanceMode.init(rawValue:)) {
            model.store.updateSettings { $0.appearance = a }
        }
    }

    static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Demo screenshots: which Statistics tab / scroll position / completed project to show first.
    static var statsTab: String? { env["ATHLOS_DEMO"] == "1" ? env["ATHLOS_DEMO_STATS"] : nil }
    static var showcaseDetail: Bool { env["ATHLOS_DEMO"] == "1" && env["ATHLOS_DEMO_SHOWCASE_DETAIL"] == "1" }
}
