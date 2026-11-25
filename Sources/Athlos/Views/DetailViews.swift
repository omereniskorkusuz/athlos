import SwiftUI
import AthlosCore

/// Project detail: summary, top-level topics, notes, actions.
struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    @State private var confirmDelete = false

    var body: some View {
        if let p = model.store.project(projectID) {
            let now = model.now
            let totals = model.store.rolledUpTotals(projectID: p.id, now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        ProjectIconView(project: p, size: 64, images: model.store.images)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name).font(.largeTitle.bold())
                            Text("Created \(Fmt.date(p.createdAt))").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        StatTile(title: "Today", value: Fmt.hm(model.store.projectSeconds(p.id, in: Stats.dayInterval(now), now: now)), systemImage: "sun.max", tint: .green)
                        StatTile(title: "Total", value: Fmt.hm(model.store.projectSeconds(p.id, now: now)), systemImage: "sum", tint: p.color)
                        StatTile(title: "Subtopic", value: "\(model.store.topics.filter { $0.projectID == p.id }.count)", systemImage: "list.bullet.indent", tint: .secondary)
                    }
                    if p.manualSeconds > 0 {
                        Label("Includes \(Fmt.hm(p.manualSeconds)) of past time entered manually.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    // Buttons with labels in a wide window, icon-only (with a tooltip) in a narrow one.
                    ViewThatFits(in: .horizontal) {
                        actionRow(p, style: .titleAndIcon, completeTitle: "Mark as completed")
                        actionRow(p, style: .titleAndIcon, completeTitle: "Finished")
                        actionRow(p, style: .iconOnly, completeTitle: "Finished")
                    }

                    let roots = model.store.children(projectID: p.id, parentID: nil)
                    if !roots.isEmpty {
                        Text("Subtopics").font(.headline)
                        BreakdownList(items: roots.map { ($0.name, totals[$0.id] ?? 0, $0.id) }, color: p.color) { id in
                            model.treeSelection = .topic(id)
                        }
                    }
                    NotesSection(projectID: p.id, topicID: nil)
                }
                .padding(24)
            }
            .confirmationDialog("Delete project “\(p.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete project and all its entries", role: .destructive) {
                    model.treeSelection = nil
                    model.store.deleteProject(p.id)
                }
            } message: {
                Text("All subtopics, time entries and notes are permanently deleted. This can't be undone (except from automatic backups).")
            }
        }
    }

    /// Project action buttons. Drawn with labels or icon-only depending on `style`.
    private func actionRow<S: LabelStyle>(_ p: Project, style: S, completeTitle: LocalizedStringKey) -> some View {
        HStack {
            Button { model.start(projectID: p.id, topicID: nil) } label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .help("Start")
            Button { model.newTopicRequest = NewTopicRequest(projectID: p.id, parentID: nil) } label: { Label("Subtopic", systemImage: "plus") }
                .help("Add subtopic")
            Button { model.projectEditor = ProjectEditorRequest(project: p) } label: { Label("Edit", systemImage: "pencil") }
                .help("Edit")
            Button { withAnimation { model.store.setProject(p.id, completed: true) }; model.treeSelection = nil } label: {
                Label(completeTitle, systemImage: "checkmark.seal")
            }
            .help("Mark as completed (moves to Completed)")
            Spacer(minLength: 12)
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                .help("Delete project")
        }
        .labelStyle(style)
        .controlSize(.large)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Subtopic detail.
struct TopicDetailView: View {
    @Environment(AppModel.self) private var model
    let topicID: UUID

    var body: some View {
        if let t = model.store.topic(topicID), let p = model.store.project(t.projectID) {
            let now = model.now
            let totals = model.store.rolledUpTotals(projectID: p.id, now: now)
            let isActive = model.store.runtime.topicID == t.id && model.timer.phase != .idle
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Path (breadcrumb) – clickable
                    HStack(spacing: 4) {
                        Button(p.name) { model.treeSelection = .project(p.id) }.buttonStyle(.link)
                        ForEach(model.store.ancestry(of: t.id).dropLast()) { a in
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            Button(a.name) { model.treeSelection = .topic(a.id) }.buttonStyle(.link)
                        }
                    }
                    .font(.callout)
                    Text(t.name).font(.largeTitle.bold())

                    HStack(spacing: 12) {
                        StatTile(title: "Today", value: Fmt.hm(model.store.topicSeconds(t.id, in: Stats.dayInterval(now), now: now)), systemImage: "sun.max", tint: .green)
                        StatTile(title: "Total", value: Fmt.hm(totals[t.id] ?? 0), systemImage: "sum", tint: p.color)
                        StatTile(title: "Entries", value: "\(model.store.entries.filter { $0.topicID == t.id && $0.kind == .work }.count)", systemImage: "list.number", tint: .secondary)
                    }

                    HStack {
                        if isActive {
                            Label(model.timer.phase == .working ? "In progress" : "Session open", systemImage: "record.circle")
                                .foregroundStyle(.green)
                        } else {
                            Button { model.start(projectID: p.id, topicID: t.id) } label: { Label("Start", systemImage: "play.fill") }
                                .buttonStyle(.borderedProminent)
                        }
                        Button { model.newTopicRequest = NewTopicRequest(projectID: p.id, parentID: t.id); model.expandedNodes.insert(t.id) } label: {
                            Label("Subtopic", systemImage: "plus")
                        }
                        Spacer()
                    }
                    .controlSize(.large)

                    let kids = model.store.children(projectID: p.id, parentID: t.id)
                    if !kids.isEmpty {
                        Text("Subtopics").font(.headline)
                        BreakdownList(items: kids.map { ($0.name, totals[$0.id] ?? 0, $0.id) }, color: p.color) { id in
                            model.expandedNodes.insert(t.id)
                            model.treeSelection = .topic(id)
                        }
                    }
                    NotesSection(projectID: p.id, topicID: t.id)
                }
                .padding(24)
            }
        }
    }
}

/// Topic → time list with proportional mini bars.
struct BreakdownList: View {
    let items: [(name: String, seconds: TimeInterval, id: UUID)]
    let color: Color
    var onSelect: ((UUID) -> Void)?

    var body: some View {
        let maxValue = max(items.map(\.seconds).max() ?? 1, 1)
        VStack(spacing: 6) {
            ForEach(items, id: \.id) { item in
                Button { onSelect?(item.id) } label: {
                    HStack {
                        Text(item.name).lineLimit(1)
                        Spacer()
                        GeometryReader { geo in
                            Capsule().fill(color.opacity(0.75))
                                .frame(width: max(3, geo.size.width * item.seconds / maxValue))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .frame(width: 120, height: 6)
                        Text(Fmt.hm(item.seconds)).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Note list + quick note (⌘↩).
struct NotesSection: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    let topicID: UUID?
    @State private var text = ""
    @State private var includeChildren = false
    @FocusState private var focused: Bool

    var body: some View {
        let notes = model.store.notes(projectID: projectID, topicID: topicID, includeDescendants: includeChildren)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notes").font(.headline)
                Spacer()
                Toggle("Include subtopic notes", isOn: $includeChildren)
                    .toggleStyle(.checkbox).font(.caption)
            }
            HStack(alignment: .bottom) {
                TextField("New note… (⌘↩)", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                Button("Add") {
                    model.store.addNote(text, projectID: projectID, topicID: topicID)
                    text = ""
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if notes.isEmpty {
                Text("No notes yet.").foregroundStyle(.secondary).font(.callout)
            }
            ForEach(notes) { n in
                NoteRow(note: n, showPath: includeChildren && n.topicID != topicID)
            }
        }
    }
}

struct NoteRow: View {
    @Environment(AppModel.self) private var model
    let note: Note
    var showPath = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Fmt.dateTime(note.createdAt)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if showPath {
                    Text(model.store.pathString(projectID: note.projectID, topicID: note.topicID))
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                if note.entryID != nil {
                    Image(systemName: "clock").font(.caption2).foregroundStyle(.tertiary).help("Linked to a time entry")
                }
                Spacer()
                Button(role: .destructive) { withAnimation { model.store.deleteNote(note.id) } } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete note")
            }
            Text(note.text).textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}
