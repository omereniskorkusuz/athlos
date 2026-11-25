import SwiftUI
import Charts
import AthlosCore

/// "Completed" page: gallery of finished projects.
struct ShowcaseView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Project?

    var body: some View {
        let completed = model.store.projects(status: .completed)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let now = model.now
        let totalSeconds = completed.reduce(0) { $0 + model.store.projectSeconds($1.id, now: now) }

        Group {
            if completed.isEmpty {
                EmptyStateView(title: "No completed projects yet", systemImage: "trophy",
                               message: "Projects you mark as “Completed” are shown here. You can also add projects you finished before, with their logo and the time you spent.",
                               actionTitle: "Add past project",
                               action: { model.projectEditor = ProjectEditorRequest(project: nil, startCompleted: true) })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Completed Work").font(Theme.display(32, weight: .bold))
                                Text("\(completed.count) projects · \(Fmt.hoursCompact(totalSeconds))")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 18)], spacing: 18) {
                            ForEach(completed) { p in
                                Button { selected = p } label: {
                                    ShowcaseCard(project: p, seconds: model.store.projectSeconds(p.id, now: now))
                                }
                                .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Details") { selected = p }
                                        Button("Edit…") { model.projectEditor = ProjectEditorRequest(project: p) }
                                        Button("Move back to active") { withAnimation { model.store.setProject(p.id, completed: false) } }
                                    }
                            }
                        }
                    }
                    .padding(28)
                }
            }
        }
        .navigationTitle("Completed")
        .toolbar {
            Button { model.projectEditor = ProjectEditorRequest(project: nil, startCompleted: true) } label: {
                Label("Add past project", systemImage: "plus")
            }
            .help("Add a project you finished before, with its logo and time")
        }
        .onAppear {
            if DemoData.showcaseDetail, selected == nil {
                selected = model.store.projects(status: .completed).max { model.store.projectSeconds($0.id, now: Date()) < model.store.projectSeconds($1.id, now: Date()) }
            }
        }
        .sheet(item: $selected) { p in ShowcaseDetailView(projectID: p.id).athlosPage().tint(Theme.accent) }
    }
}

struct ShowcaseCard: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let seconds: TimeInterval
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 12) {
            ProjectIconView(project: project, size: 112, images: model.store.images)
                .shadow(color: project.color.opacity(hovering ? 0.5 : 0.25), radius: hovering ? 16 : 8, y: 4)
            Text(project.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Text(Fmt.hoursCompact(seconds))
                .font(Theme.display(26, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(project.color)
            if let done = project.completedAt {
                Text(Fmt.date(done)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .athlosCard(radius: 20)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(project.color.opacity(hovering ? 0.6 : 0), lineWidth: 2))
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.spring(duration: 0.3), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(project.name), \(Fmt.spoken(seconds))"))
    }
}

/// Completed project detail: dates, total days, time by subtopic, notes.
struct ShowcaseDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID

    var body: some View {
        if let p = model.store.project(projectID) {
            let now = model.now
            let store = model.store
            let entries = store.entries.filter { $0.projectID == p.id && $0.kind == .work }
            let firstWork = entries.map(\.start).min()
            let startDate = min(p.createdAt, firstWork ?? p.createdAt)
            let endDate = p.completedAt ?? now
            let days = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate),
                                                         to: Calendar.current.startOfDay(for: endDate)).day ?? 0) + 1
            let activeDays = Set(entries.map { Calendar.current.startOfDay(for: $0.start) }).count
            let totals = store.rolledUpTotals(projectID: p.id, now: now)
            let roots = store.children(projectID: p.id, parentID: nil)
            let untracked = store.projectSeconds(p.id, now: now) - roots.reduce(0) { $0 + (totals[$1.id] ?? 0) }

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 20) {
                            ProjectIconView(project: p, size: 120, images: store.images)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(p.name).font(Theme.display(32, weight: .bold))
                                Text(Fmt.hoursCompact(store.projectSeconds(p.id, now: now)))
                                    .font(Theme.display(26)).foregroundStyle(p.color)
                                Label("Finished", systemImage: "checkmark.seal.fill").foregroundStyle(Color.goalColor)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                            StatTile(title: "Started", value: Fmt.date(startDate), systemImage: "flag", tint: Theme.brand)
                            StatTile(title: "End", value: Fmt.date(endDate), systemImage: "flag.checkered", tint: .goalColor)
                            StatTile(title: "Total days", value: "\(days)", systemImage: "calendar", tint: Theme.brandDeep)
                            StatTile(title: "Days worked", value: "\(activeDays)", systemImage: "calendar.badge.checkmark", tint: Theme.rest)
                        }
                        if !roots.isEmpty || untracked > 0 {
                            Text("Time by subtopic").font(Theme.heading)
                            let items = roots.map { ($0.name, totals[$0.id] ?? 0) }.filter { $0.1 > 0 }
                                + (untracked > 59 ? [(String(localized: "General / entered manually"), untracked)] : [])
                            Chart(items, id: \.0) { item in
                                BarMark(x: .value("Time", item.1 / 3600), y: .value("Topic", item.0))
                                    .foregroundStyle(p.color.gradient)
                                    .cornerRadius(4)
                                    .annotation(position: .trailing) {
                                        Text(Fmt.hm(item.1)).font(.caption).foregroundStyle(.secondary)
                                    }
                            }
                            .chartXAxisLabel("hours")
                            .frame(height: CGFloat(max(items.count, 1)) * 34 + 30)
                        }
                        let notes = store.notes(projectID: p.id, topicID: nil, includeDescendants: true)
                        if !notes.isEmpty {
                            Text("Notes").font(Theme.heading)
                            ForEach(notes) { NoteRow(note: $0, showPath: $0.topicID != nil) }
                        }
                    }
                    .padding(24)
                }
                Divider()
                HStack {
                    Button("Move back to active") {
                        model.store.setProject(p.id, completed: false)
                        dismiss()
                    }
                    Button("Edit…") {
                        dismiss()
                        model.projectEditor = ProjectEditorRequest(project: p)
                    }
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
                }
                .padding(14)
            }
            .frame(width: 620, height: 640)
        }
    }
}
