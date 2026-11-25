import Foundation
import Observation

/// The app's single source of truth (repository). Every change goes through here and is written to disk at once.
/// If we move to SwiftData later, only the inside of this class changes; its interface stays the same.
@MainActor
@Observable
public final class AppStore {
    public private(set) var projects: [Project] = []
    public private(set) var topics: [Topic] = []
    public private(set) var entries: [TimeEntry] = []
    public private(set) var notes: [Note] = []
    public private(set) var settings = AppSettings()
    public var runtime = RuntimeState()

    /// Last save error (can be shown in the UI).
    public private(set) var lastSaveError: String?

    @ObservationIgnored private let persistence: DataPersisting?
    @ObservationIgnored public let images: ImageStore?

    /// - Parameter persistence: `nil` → in memory only (for tests).
    public init(persistence: DataPersisting? = nil, images: ImageStore? = nil) {
        self.persistence = persistence
        self.images = images
        if let persistence {
            do {
                if let loaded = try persistence.load() { apply(loaded) }
            } catch {
                // Move a corrupt file aside instead of deleting it; the user can restore from a backup.
                lastSaveError = "Could not read data: \(error.localizedDescription)"
                if let file = (persistence as? JSONFilePersistence)?.url {
                    let broken = file.deletingPathExtension().appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970)).json")
                    try? FileManager.default.moveItem(at: file, to: broken)
                }
            }
        }
    }

    // MARK: All data

    public var snapshot: AppData {
        var d = AppData()
        d.projects = projects
        d.topics = topics
        d.entries = entries
        d.notes = notes
        d.settings = settings
        d.runtime = runtime
        return d
    }

    /// Replaces all data (import).
    public func replaceAll(with data: AppData) {
        apply(data)
        save()
    }

    private func apply(_ d: AppData) {
        projects = d.projects
        topics = d.topics
        entries = d.entries
        notes = d.notes
        settings = d.settings
        runtime = d.runtime
    }

    public func save() {
        guard let persistence else { return }
        do {
            try persistence.save(snapshot)
            lastSaveError = nil
        } catch {
            lastSaveError = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: Settings

    public func updateSettings(_ change: (inout AppSettings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        settings = s
        save()
    }

    public func updateRuntime(save shouldSave: Bool = true, _ change: (inout RuntimeState) -> Void) {
        change(&runtime)
        if shouldSave { save() }
    }

    // MARK: Projects

    public func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    public func projects(status: ProjectStatus) -> [Project] {
        projects.filter { $0.status == status }.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    @discardableResult
    public func addProject(name: String, icon: ProjectIcon = .default, colorHex: String = "#0A84FF",
                           manualSeconds: TimeInterval = 0, status: ProjectStatus = .active,
                           createdAt: Date = Date()) -> Project {
        let p = Project(name: name.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon, colorHex: colorHex,
                        status: status, createdAt: createdAt,
                        completedAt: status == .completed ? createdAt : nil,
                        manualSeconds: manualSeconds,
                        sortIndex: (projects.map(\.sortIndex).max() ?? -1) + 1)
        projects.append(p)
        save()
        return p
    }

    public func updateProject(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        // Delete the old image if it's no longer used.
        if case .image(let old) = projects[i].icon, project.icon != projects[i].icon { images?.delete(old) }
        projects[i] = project
        save()
    }

    /// Marks a project as completed or back as active.
    public func setProject(_ id: UUID, completed: Bool, at date: Date = Date()) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].status = completed ? .completed : .active
        projects[i].completedAt = completed ? date : nil
        save()
    }

    /// Deletes a project with all its topics, entries and notes.
    public func deleteProject(_ id: UUID) {
        if let p = project(id), case .image(let name) = p.icon { images?.delete(name) }
        projects.removeAll { $0.id == id }
        topics.removeAll { $0.projectID == id }
        entries.removeAll { $0.projectID == id && !$0.isRunning }
        notes.removeAll { $0.projectID == id }
        if runtime.projectID == id {
            entries.removeAll { $0.projectID == id }
            runtime = RuntimeState()
        }
        save()
    }

    // MARK: Subtopics (tree)

    public func topic(_ id: UUID?) -> Topic? {
        guard let id else { return nil }
        return topics.first { $0.id == id }
    }

    /// Direct children of a node, sorted.
    public func children(projectID: UUID, parentID: UUID?) -> [Topic] {
        topics.filter { $0.projectID == projectID && $0.parentID == parentID }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    /// All descendants of a node (not including itself).
    public func descendantIDs(of id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var stack = [id]
        // The parent → children map is built once (O(n) on large trees).
        let byParent = Dictionary(grouping: topics.filter { $0.parentID != nil }, by: { $0.parentID! })
        while let current = stack.popLast() {
            for child in byParent[current] ?? [] where !result.contains(child.id) {
                result.insert(child.id)
                stack.append(child.id)
            }
        }
        return result
    }

    /// Topic chain from the root to the node.
    public func ancestry(of id: UUID) -> [Topic] {
        var chain: [Topic] = []
        var current = topic(id)
        var guardCount = 0
        while let t = current, guardCount < 10_000 {
            chain.insert(t, at: 0)
            current = topic(t.parentID)
            guardCount += 1
        }
        return chain
    }

    /// "Project > Topic > Subtopic" path.
    public func pathComponents(projectID: UUID?, topicID: UUID?) -> [String] {
        var parts: [String] = []
        if let p = project(projectID) { parts.append(p.name) }
        if let topicID { parts += ancestry(of: topicID).map(\.name) }
        return parts
    }

    public func pathString(projectID: UUID?, topicID: UUID?) -> String {
        pathComponents(projectID: projectID, topicID: topicID).joined(separator: " › ")
    }

    @discardableResult
    public func addTopic(name: String, projectID: UUID, parentID: UUID? = nil) -> Topic? {
        guard project(projectID) != nil else { return nil }
        if let parentID, topic(parentID)?.projectID != projectID { return nil }
        let siblings = children(projectID: projectID, parentID: parentID)
        let t = Topic(projectID: projectID, parentID: parentID,
                      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                      sortIndex: (siblings.map(\.sortIndex).max() ?? -1) + 1)
        topics.append(t)
        save()
        return t
    }

    public func renameTopic(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[i].name = trimmed
        save()
    }

    /// Deletes a topic and all its subtopics.
    /// Time entries are NOT lost: they move to the deleted topic's parent (or the project root).
    /// Notes linked to deleted topics also move to the parent topic.
    public func deleteTopic(_ id: UUID) {
        guard let t = topic(id) else { return }
        let removed = descendantIDs(of: id).union([id])
        for i in entries.indices where entries[i].topicID.map(removed.contains) == true {
            entries[i].topicID = t.parentID
        }
        for i in notes.indices where notes[i].topicID.map(removed.contains) == true {
            notes[i].topicID = t.parentID
        }
        if let rt = runtime.topicID, removed.contains(rt) { runtime.topicID = t.parentID }
        topics.removeAll { removed.contains($0.id) }
        save()
    }

    /// Is the move valid? (A node can't be moved under itself.)
    public func canMove(_ id: UUID, toParent parentID: UUID?, projectID: UUID) -> Bool {
        guard topic(id) != nil, project(projectID) != nil else { return false }
        guard let parentID else { return true }
        if parentID == id || descendantIDs(of: id).contains(parentID) { return false }
        return topic(parentID)?.projectID == projectID
    }

    /// Moves a topic under a new parent / project and positions it among its siblings.
    /// - Parameter beforeID: insert before this sibling; `nil` → at the end.
    @discardableResult
    public func moveTopic(_ id: UUID, toProject projectID: UUID, parent parentID: UUID?, before beforeID: UUID? = nil) -> Bool {
        guard canMove(id, toParent: parentID, projectID: projectID), beforeID != id,
              let index = topics.firstIndex(where: { $0.id == id }) else { return false }
        let oldProject = topics[index].projectID
        topics[index].parentID = parentID
        topics[index].projectID = projectID

        // If the project changed, the whole subtree and its entries move to the new project too.
        if oldProject != projectID {
            let subtree = descendantIDs(of: id).union([id])
            for i in topics.indices where subtree.contains(topics[i].id) { topics[i].projectID = projectID }
            for i in entries.indices where entries[i].topicID.map(subtree.contains) == true { entries[i].projectID = projectID }
            for i in notes.indices where notes[i].topicID.map(subtree.contains) == true { notes[i].projectID = projectID }
            if let rt = runtime.topicID, subtree.contains(rt) { runtime.projectID = projectID }
        }

        // Renumber the siblings.
        var siblings = children(projectID: projectID, parentID: parentID).filter { $0.id != id }
        let insertAt = beforeID.flatMap { b in siblings.firstIndex { $0.id == b } } ?? siblings.count
        siblings.insert(topics[index], at: insertAt)
        for (order, s) in siblings.enumerated() {
            if let i = topics.firstIndex(where: { $0.id == s.id }) { topics[i].sortIndex = order }
        }
        save()
        return true
    }

    /// Sets the sibling order to the given ID order (drag-and-drop reordering).
    public func setSiblingOrder(_ ids: [UUID]) {
        for (order, id) in ids.enumerated() {
            if let i = topics.firstIndex(where: { $0.id == id }) { topics[i].sortIndex = order }
        }
        save()
    }

    /// Moves up / down one place among siblings.
    public func shiftTopic(_ id: UUID, by delta: Int) {
        guard let t = topic(id) else { return }
        let siblings = children(projectID: t.projectID, parentID: t.parentID)
        guard let i = siblings.firstIndex(where: { $0.id == id }) else { return }
        let target = i + delta
        guard target >= 0, target < siblings.count else { return }
        let before: UUID? = delta < 0 ? siblings[target].id : (target + 1 < siblings.count ? siblings[target + 1].id : nil)
        moveTopic(id, toProject: t.projectID, parent: t.parentID, before: before)
    }

    // MARK: Time entries

    public var openEntry: TimeEntry? { entries.last(where: { $0.isRunning }) }

    public func entry(_ id: UUID) -> TimeEntry? { entries.first { $0.id == id } }

    @discardableResult
    public func addEntry(_ e: TimeEntry) -> TimeEntry {
        entries.append(e)
        save()
        return e
    }

    public func updateEntry(_ e: TimeEntry, save shouldSave: Bool = true) {
        guard let i = entries.firstIndex(where: { $0.id == e.id }) else { return }
        entries[i] = e
        if shouldSave { save() }
    }

    public func deleteEntry(_ id: UUID) {
        entries.removeAll { $0.id == id }
        for i in notes.indices where notes[i].entryID == id { notes[i].entryID = nil }
        save()
    }

    /// Entries of the same kind that overlap the given range (for the warning when adding/editing by hand).
    /// Overlapping entries are counted twice in the statistics.
    public func overlappingEntries(start: Date, end: Date, kind: EntryKind = .work,
                                   excluding id: UUID? = nil, now: Date = Date()) -> [TimeEntry] {
        entries.filter { e in
            e.id != id && e.kind == kind && e.start < end && (e.end ?? now) > start
        }
        .sorted { $0.start < $1.start }
    }

    /// Manual entry for work you forgot to track.
    @discardableResult
    public func addManualEntry(projectID: UUID, topicID: UUID?, kind: EntryKind = .work, start: Date, end: Date) -> TimeEntry? {
        guard end > start else { return nil }
        return addEntry(TimeEntry(projectID: projectID, topicID: topicID, kind: kind, start: start, end: end, isManual: true))
    }

    /// Recently used distinct topics (newest first).
    public func recentTargets(limit: Int = 5) -> [(projectID: UUID, topicID: UUID?)] {
        var seen = Set<String>()
        var result: [(UUID, UUID?)] = []
        for e in entries.sorted(by: { $0.start > $1.start }) where e.kind == .work {
            guard project(e.projectID)?.status == .active else { continue }
            if let tid = e.topicID, topic(tid) == nil { continue }
            let key = "\(e.projectID)-\(e.topicID?.uuidString ?? "")"
            if seen.insert(key).inserted { result.append((e.projectID, e.topicID)) }
            if result.count >= limit { break }
        }
        return result.map { (projectID: $0.0, topicID: $0.1) }
    }

    // MARK: Notes

    @discardableResult
    public func addNote(_ text: String, projectID: UUID?, topicID: UUID?, entryID: UUID? = nil, at date: Date = Date()) -> Note? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let n = Note(text: trimmed, createdAt: date, projectID: projectID, topicID: topicID, entryID: entryID)
        notes.append(n)
        save()
        return n
    }

    public func updateNote(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].text = text
        save()
    }

    public func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    /// Notes of a topic; with `includeDescendants` also those of its subtopics.
    public func notes(projectID: UUID, topicID: UUID?, includeDescendants: Bool = false) -> [Note] {
        let ids: Set<UUID>? = topicID.map { includeDescendants ? descendantIDs(of: $0).union([$0]) : [$0] }
        return notes.filter { n in
            guard n.projectID == projectID else { return false }
            guard let ids else { return includeDescendants || n.topicID == nil }
            return n.topicID.map(ids.contains) ?? false
        }.sorted { $0.createdAt > $1.createdAt }
    }
}
