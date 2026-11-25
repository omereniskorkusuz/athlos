import SwiftUI
import AthlosCore

/// Time entry history: list, filter, edit, delete, add manually.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    enum Period: String, CaseIterable { case today, week, month, all }
    enum KindFilter: String, CaseIterable { case all, work, rest }

    @State private var period: Period = .week
    @State private var kindFilter: KindFilter = .all
    @State private var projectFilter: UUID?
    @State private var selection = Set<TimeEntry.ID>()
    @State private var editing: EntryEditRequest?
    @State private var confirmDelete: Set<UUID> = []

    private var rows: [TimeEntry] {
        let now = model.now
        let cal = Calendar.current
        let from: Date? = switch period {
        case .today: cal.startOfDay(for: now)
        case .week: cal.date(byAdding: .day, value: -7, to: now)
        case .month: cal.date(byAdding: .month, value: -1, to: now)
        case .all: nil
        }
        return model.store.entries.filter { e in
            if let from, (e.end ?? now) < from { return false }
            if let projectFilter, e.projectID != projectFilter { return false }
            switch kindFilter {
            case .all: return true
            case .work: return e.kind == .work
            case .rest: return e.kind == .breakTime
            }
        }
        .sorted { $0.start > $1.start }
    }

    var body: some View {
        let rows = rows
        let now = model.now
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Period", selection: $period) {
                    Text("Today").tag(Period.today)
                    Text("7 days").tag(Period.week)
                    Text("30 days").tag(Period.month)
                    Text("All time").tag(Period.all)
                }
                .pickerStyle(.segmented).fixedSize()
                Picker("Project", selection: $projectFilter) {
                    Text("All projects").tag(UUID?.none)
                    ForEach(model.store.projects) { p in Text(p.name).tag(UUID?.some(p.id)) }
                }
                .labelsHidden()
                .fixedSize()
                Picker("Type", selection: $kindFilter) {
                    Text("All").tag(KindFilter.all)
                    Text("Work").tag(KindFilter.work)
                    Text("Break").tag(KindFilter.rest)
                }
                .fixedSize()
                Spacer()
                Text("Total: \(Fmt.hm(Stats.seconds(rows, kind: .work, now: now)))")
                    .monospacedDigit().foregroundStyle(.secondary)
                Button { editing = EntryEditRequest(entry: nil) } label: { Label("Manual entry", systemImage: "plus") }
                    .disabled(model.store.projects.isEmpty)
            }
            .padding(12)
            Divider()
            if rows.isEmpty {
                EmptyStateView(title: "No entries", systemImage: "clock.badge.questionmark",
                               message: "No time entries match these filters. You can add work you forgot to track by hand.")
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("Date") { e in Text(Fmt.date(e.start)) }
                        .width(min: 90, ideal: 110)
                    TableColumn("Time") { e in
                        Text("\(Fmt.time(e.start)) – \(e.end.map(Fmt.time) ?? "…")").monospacedDigit()
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn("Duration") { e in
                        Text(Fmt.clock(e.duration(now: now))).monospacedDigit()
                            .foregroundStyle(e.isRunning ? .green : .primary)
                    }
                    .width(min: 70, ideal: 80)
                    TableColumn("Type") { e in
                        Label(e.kind == .work ? "Work" : "Break", systemImage: e.kind == .work ? "hammer" : "cup.and.saucer")
                            .foregroundStyle(e.kind == .work ? Color.primary : Color.orange)
                    }
                    .width(min: 80, ideal: 90)
                    TableColumn("Project › Topic") { e in
                        HStack(spacing: 6) {
                            if let p = model.store.project(e.projectID) { Circle().fill(p.color).frame(width: 8, height: 8) }
                            Text(model.store.pathString(projectID: e.projectID, topicID: e.topicID)).lineLimit(1)
                            if e.isManual { Image(systemName: "hand.raised").font(.caption).foregroundStyle(.secondary).help("Added manually") }
                        }
                    }
                }
                .contextMenu(forSelectionType: TimeEntry.ID.self) { ids in
                    if ids.count == 1, let id = ids.first, let e = model.store.entry(id) {
                        Button("Edit…") { editing = EntryEditRequest(entry: e) }
                            .disabled(e.isRunning)
                    }
                    Button("Delete…", role: .destructive) { confirmDelete = ids }
                        .disabled(ids.isEmpty || ids.contains { model.store.entry($0)?.isRunning == true })
                } primaryAction: { ids in
                    if ids.count == 1, let e = ids.first.flatMap(model.store.entry), !e.isRunning { editing = EntryEditRequest(entry: e) }
                }
                .onDeleteCommand { confirmDelete = selection.filter { model.store.entry($0)?.isRunning == false } }
            }
        }
        .sheet(item: $editing) { req in EntryEditorView(request: req) }
        .confirmationDialog("Delete \(confirmDelete.count) entries?", isPresented: Binding(get: { !confirmDelete.isEmpty }, set: { if !$0 { confirmDelete = [] } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                for id in confirmDelete { model.store.deleteEntry(id) }
                selection.subtract(confirmDelete)
                confirmDelete = []
            }
        } message: {
            Text("Deleted time is removed from your statistics.")
        }
    }
}

struct EntryEditRequest: Identifiable {
    let id = UUID()
    let entry: TimeEntry?
}

/// Edit an entry / add one manually.
struct EntryEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: EntryEditRequest

    @State private var target: String = ""
    @State private var kind: EntryKind = .work
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()

    var body: some View {
        let targets = model.store.flattenedTargets(includeCompleted: true)
        let valid = end > start && !target.isEmpty
        VStack(spacing: 0) {
            Form {
                Picker("Topic", selection: $target) {
                    ForEach(targets) { t in
                        Text(String(repeating: "   ", count: t.depth) + (t.path.components(separatedBy: " › ").last ?? "")).tag(t.id)
                    }
                }
                Picker("Type", selection: $kind) {
                    Text("Work").tag(EntryKind.work)
                    Text("Break").tag(EntryKind.breakTime)
                }
                .pickerStyle(.segmented)
                DatePicker("Started", selection: $start)
                DatePicker("End", selection: $end)
                LabeledContent("Duration") {
                    Text(end > start ? Fmt.hm(end.timeIntervalSince(start)) : String(localized: "End must be after start"))
                        .foregroundStyle(end > start ? Color.secondary : Color.red)
                }
                // Overlap warning: the same time shouldn't be counted twice.
                if end > start {
                    let overlaps = model.store.overlappingEntries(start: start, end: end, kind: kind, excluding: request.entry?.id)
                    if let first = overlaps.first {
                        Label {
                            Text("This range overlaps \(overlaps.count) entries (e.g. \(Fmt.time(first.start))–\(first.end.map(Fmt.time) ?? "…"), \(model.store.pathString(projectID: first.projectID, topicID: first.topicID))). If you save, this time is counted twice.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.entry == nil ? "Add" : "Save") { save(targets) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
            .padding(14)
        }
        .frame(width: 480, height: 430)
        .onAppear {
            if let e = request.entry {
                target = "\(e.projectID)-\(e.topicID?.uuidString ?? "root")"
                kind = e.kind
                start = e.start
                end = e.end ?? Date()
            } else {
                if let first = targets.first { target = first.id }
                let cal = Calendar.current
                start = cal.date(bySettingHour: cal.component(.hour, from: Date()) - 1, minute: 0, second: 0, of: Date()) ?? start
                end = start.addingTimeInterval(3600)
            }
        }
    }

    private func save(_ targets: [PickTarget]) {
        guard let t = targets.first(where: { $0.id == target }), end > start else { return }
        if var e = request.entry {
            e.projectID = t.projectID
            e.topicID = t.topicID
            e.kind = kind
            e.start = start
            e.end = end
            model.store.updateEntry(e)
        } else {
            model.store.addManualEntry(projectID: t.projectID, topicID: t.topicID, kind: kind, start: start, end: end)
        }
        dismiss()
    }
}
