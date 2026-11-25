import SwiftUI
import AthlosCore

/// A selectable target: a project or a subtopic at any depth.
struct PickTarget: Identifiable, Hashable {
    var id: String { "\(projectID)-\(topicID?.uuidString ?? "root")" }
    let projectID: UUID
    let topicID: UUID?
    let path: String
    let depth: Int
}

extension AppStore {
    /// All nodes of active projects, flattened in tree order.
    func flattenedTargets(includeCompleted: Bool = false) -> [PickTarget] {
        var result: [PickTarget] = []
        let ps = includeCompleted ? projects.sorted { $0.sortIndex < $1.sortIndex } : projects(status: .active)
        for p in ps {
            result.append(PickTarget(projectID: p.id, topicID: nil, path: p.name, depth: 0))
            func walk(_ parent: UUID?, prefix: String, depth: Int) {
                for t in children(projectID: p.id, parentID: parent) {
                    let path = prefix + " › " + t.name
                    result.append(PickTarget(projectID: p.id, topicID: t.id, path: path, depth: depth))
                    walk(t.id, prefix: path, depth: depth + 1)
                }
            }
            walk(nil, prefix: p.name, depth: 1)
        }
        return result
    }
}

/// Quick topic picker with search (⌘K).
struct QuickPickerView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var highlighted: PickTarget?
    @FocusState private var searchFocused: Bool

    private var results: [PickTarget] {
        let all = model.store.flattenedTargets()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        // Every word must appear in the path (e.g. "ser raid" → "Server Storage › Disk › RAID").
        let words = q.split(separator: " ").map { String($0).searchFolded }
        return all.filter { t in
            let path = t.path.searchFolded
            return words.allSatisfy { path.contains($0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search projects or topics…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit { choose(highlighted ?? results.first) }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
            }
            .padding(14)
            Divider()
            if results.isEmpty {
                VStack(spacing: 10) {
                    Text("No results").foregroundStyle(.secondary)
                    if model.store.projects(status: .active).isEmpty {
                        Button("Create a new project") { model.showQuickPicker = false; model.newProject() }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollViewReader { proxy in
                    List(results, selection: Binding(get: { highlighted?.id }, set: { id in highlighted = results.first { $0.id == id } })) { t in
                        row(t)
                            .tag(t.id)
                            .id(t.id)
                            .onTapGesture(count: 2) { choose(t) }
                    }
                    .listStyle(.plain)
                    .onChange(of: highlighted) { _, h in if let h { proxy.scrollTo(h.id) } }
                }
                .frame(minHeight: 300)
            }
            Divider()
            HStack {
                Text("↩ choose · ↑↓ move · double-click to start").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.showQuickPicker = false }.keyboardShortcut(.cancelAction)
                Button(model.quickPickerSwitchOnly ? "Switch" : "Start") { choose(highlighted ?? results.first) }
                    .buttonStyle(.borderedProminent)
                    .disabled(results.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 520, height: 460)
        .onAppear { searchFocused = true }
        .onChange(of: query) { highlighted = results.first }
    }

    private func row(_ t: PickTarget) -> some View {
        HStack(spacing: 8) {
            if t.topicID == nil, let p = model.store.project(t.projectID) {
                ProjectIconView(project: p, size: 20, images: model.store.images)
                Text(p.name).fontWeight(.semibold)
            } else {
                Image(systemName: "number").foregroundStyle(.tertiary).font(.caption)
                    .padding(.leading, CGFloat(t.depth - 1) * 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.path.components(separatedBy: " › ").last ?? t.path)
                    if !query.isEmpty {
                        Text(t.path).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityLabel(t.path)
    }

    private func move(_ delta: Int) {
        let r = results
        guard !r.isEmpty else { return }
        let i = highlighted.flatMap { h in r.firstIndex(of: h) } ?? -1
        highlighted = r[max(0, min(r.count - 1, i + delta))]
    }

    private func choose(_ t: PickTarget?) {
        guard let t else { return }
        model.pick(projectID: t.projectID, topicID: t.topicID)
    }
}

extension String {
    /// Normalized for search: Turkish i/ı/İ/I, case and diacritics are ignored
    /// ("raid" → "RAID setup", "server" → "SERVER", "calisma" → "Çalışma").
    var searchFolded: String {
        lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
