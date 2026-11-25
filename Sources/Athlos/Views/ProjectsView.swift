import SwiftUI
import AthlosCore

/// Projects page: project/subtopic tree on the left, detail of the selected node on the right.
struct ProjectsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.store.projects(status: .active).isEmpty {
            EmptyStateView(title: "No active projects", systemImage: "folder.badge.plus",
                           message: "Create a project and add as many subtopics under it as you like.",
                           actionTitle: "New project", action: { model.newProject() })
                .navigationTitle("Projects")
        } else {
            HSplitView {
                ProjectTreeView()
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 460)
                Group {
                    switch model.treeSelection {
                    case .project(let id): ProjectDetailView(projectID: id)
                    case .topic(let id): TopicDetailView(topicID: id)
                    case nil:
                        EmptyStateView(title: "Choose a topic", systemImage: "sidebar.left",
                                       message: "Choose a project or subtopic in the tree on the left.")
                    }
                }
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItemGroup {
                    Button { model.newProject() } label: { Label("New project", systemImage: "folder.badge.plus") }
                        .help("New project (⌘N)")
                    Button { model.newTopic() } label: { Label("New subtopic", systemImage: "plus.square.on.square") }
                        .help("New subtopic (⇧⌘N)")
                }
            }
        }
    }
}

// MARK: - Tree

struct ProjectTreeView: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: Topic?
    @State private var deleting: Topic?
    @State private var moving: Topic?

    var body: some View {
        @Bindable var model = model
        let now = model.now
        List(selection: $model.treeSelection) {
            ForEach(model.store.projects(status: .active)) { p in
                let totals = model.store.rolledUpTotals(projectID: p.id, now: now)
                let today = model.store.rolledUpTotals(projectID: p.id, in: Stats.dayInterval(now), now: now)
                DisclosureGroup(isExpanded: expansion(p.id)) {
                    let roots = model.store.children(projectID: p.id, parentID: nil)
                    ForEach(roots) { t in
                        TopicTreeRow(topic: t, totals: totals, today: today,
                                     renaming: $renaming, deleting: $deleting, moving: $moving)
                    }
                    .onMove { from, to in reorder(roots, from, to) }
                } label: {
                    projectRow(p)
                }
                .tag(TreeSelection.project(p.id))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.well)
        .safeAreaInset(edge: .bottom) {
            Text("Drag to reorder · Right-click › Move… to move elsewhere")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(Theme.well)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .sheet(item: $renaming) { t in RenameSheet(topic: t).athlosPage().tint(Theme.accent) }
        .sheet(item: $moving) { t in MoveTopicSheet(topic: t).athlosPage().tint(Theme.accent) }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let d = deleting {
                    if model.treeSelection == .topic(d.id) { model.treeSelection = d.parentID.map { .topic($0) } ?? .project(d.projectID) }
                    model.store.deleteTopic(d.id)
                }
                deleting = nil
            }
        } message: {
            let count = deleting.map { model.store.descendantIDs(of: $0.id).count } ?? 0
            Text(count > 0 ? "This topic and its \(count) subtopics will be deleted. Time entries and notes move to the parent topic." : "Time entries and notes move to the parent topic.")
        }
    }

    /// Reorder siblings by drag and drop.
    private func reorder(_ siblings: [Topic], _ from: IndexSet, _ to: Int) {
        var ids = siblings.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        withAnimation { model.store.setSiblingOrder(ids) }
    }

    private func expansion(_ id: UUID) -> Binding<Bool> {
        Binding(get: { model.expandedNodes.contains(id) },
                set: { v in if v { model.expandedNodes.insert(id) } else { model.expandedNodes.remove(id) } })
    }

    private func projectRow(_ p: Project) -> some View {
        HStack(spacing: 8) {
            ProjectIconView(project: p, size: 22, images: model.store.images)
            Text(p.name).fontWeight(.semibold).lineLimit(1)
            Spacer()
            if model.store.runtime.projectID == p.id, model.store.runtime.topicID == nil, model.timer.phase == .working {
                Image(systemName: "record.circle").foregroundStyle(Theme.goldText).symbolEffect(.pulse)
            }
            Text(Fmt.hm(model.store.projectSeconds(p.id, now: model.now)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Start") { model.start(projectID: p.id, topicID: nil) }
            Button("Add subtopic") { model.newTopicRequest = NewTopicRequest(projectID: p.id, parentID: nil) }
            Button("Edit…") { model.projectEditor = ProjectEditorRequest(project: p) }
            Divider()
            Button("Mark as completed") { model.store.setProject(p.id, completed: true) }
        }
    }
}

/// A single topic row in the tree (repeats itself for its children).
struct TopicTreeRow: View {
    @Environment(AppModel.self) private var model
    let topic: Topic
    let totals: [UUID: TimeInterval]
    let today: [UUID: TimeInterval]
    @Binding var renaming: Topic?
    @Binding var deleting: Topic?
    @Binding var moving: Topic?

    var body: some View {
        let kids = model.store.children(projectID: topic.projectID, parentID: topic.id)
        Group {
            if kids.isEmpty {
                label
            } else {
                DisclosureGroup(isExpanded: Binding(get: { model.expandedNodes.contains(topic.id) },
                                                    set: { v in if v { model.expandedNodes.insert(topic.id) } else { model.expandedNodes.remove(topic.id) } })) {
                    ForEach(kids) { k in
                        TopicTreeRow(topic: k, totals: totals, today: today, renaming: $renaming, deleting: $deleting, moving: $moving)
                    }
                    .onMove { from, to in
                        var ids = kids.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        withAnimation { model.store.setSiblingOrder(ids) }
                    }
                } label: { label }
            }
        }
        .tag(TreeSelection.topic(topic.id))
    }

    private var isActive: Bool { model.store.runtime.topicID == topic.id && model.timer.phase != .idle }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: isActive ? "record.circle" : "number")
                .foregroundStyle(isActive ? AnyShapeStyle(Theme.goldText) : AnyShapeStyle(.tertiary))
                .font(.caption)
            Text(topic.name).lineLimit(1)
            Spacer()
            if let t = today[topic.id], t >= 60 {
                Text(Fmt.hm(t)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.goldText)
                    .help("Today")
            }
            Text(Fmt.hm(totals[topic.id] ?? 0))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help("Total (including subtopics)")
        }
        .contextMenu {
            Button("Start") { model.start(projectID: topic.projectID, topicID: topic.id) }
            Button("Add subtopic") {
                model.expandedNodes.insert(topic.id)
                model.newTopicRequest = NewTopicRequest(projectID: topic.projectID, parentID: topic.id)
            }
            Button("Rename…") { renaming = topic }
            Divider()
            Button("Move up") { withAnimation { model.store.shiftTopic(topic.id, by: -1) } }
            Button("Move down") { withAnimation { model.store.shiftTopic(topic.id, by: 1) } }
            Button("Move…") { moving = topic }
            if topic.parentID != nil {
                Button("Move up one level") {
                    let parent = model.store.topic(topic.parentID)
                    withAnimation { _ = model.store.moveTopic(topic.id, toProject: topic.projectID, parent: parent?.parentID) }
                }
            }
            Divider()
            Button("Delete…", role: .destructive) { deleting = topic }
        }
        .accessibilityLabel(Text("\(topic.name), total \(Fmt.spoken(totals[topic.id] ?? 0))"))
    }
}

// MARK: - Sheets

struct NewTopicSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: NewTopicRequest
    @State private var name = ""
    @State private var addAnother = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New subtopic").font(Theme.display(22))
            Text("Location: \(model.store.pathString(projectID: request.projectID, topicID: request.parentID))")
                .foregroundStyle(.secondary)
            TextField("Topic name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            Toggle("Add another after creating", isOn: $addAnother)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let t = model.store.addTopic(name: name, projectID: request.projectID, parentID: request.parentID) {
            model.expandedNodes.insert(request.projectID)
            if let p = request.parentID { model.expandedNodes.insert(p) }
            if !addAnother { model.treeSelection = .topic(t.id) }
        }
        if addAnother { name = "" } else { dismiss() }
    }
}

struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let topic: Topic
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename").font(Theme.display(22))
            TextField("Topic name", text: $name).textFieldStyle(.roundedBorder).onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { name = topic.name }
    }

    private func save() {
        model.store.renameTopic(topic.id, to: name)
        dismiss()
    }
}

/// Moves a topic to another project / parent topic.
struct MoveTopicSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let topic: Topic
    @State private var target: PickTarget?

    var body: some View {
        let invalid = model.store.descendantIDs(of: topic.id).union([topic.id])
        let targets = model.store.flattenedTargets().filter { t in t.topicID.map { !invalid.contains($0) } ?? true }
        VStack(alignment: .leading, spacing: 12) {
            Text("Move “\(topic.name)” where?").font(Theme.heading)
            List(targets, selection: Binding(get: { target?.id }, set: { id in target = targets.first { $0.id == id } })) { t in
                HStack {
                    if t.topicID == nil { Image(systemName: "folder").foregroundStyle(.secondary) }
                    Text(t.path.components(separatedBy: " › ").last ?? "")
                        .fontWeight(t.topicID == nil ? .semibold : .regular)
                        .padding(.leading, CGFloat(t.depth) * 12)
                }
                .tag(t.id)
            }
            .frame(height: 320)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move") {
                    if let t = target {
                        withAnimation { _ = model.store.moveTopic(topic.id, toProject: t.projectID, parent: t.topicID) }
                        if let p = t.topicID { model.expandedNodes.insert(p) }
                        model.expandedNodes.insert(t.projectID)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(target == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
