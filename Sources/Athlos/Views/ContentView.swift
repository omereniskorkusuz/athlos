import SwiftUI
import AthlosCore

/// Main window: sidebar + selected page. Shared sheets and alerts live here.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
        } detail: {
            Group {
                switch model.route {
                case .timer: TimerView()
                case .projects: ProjectsView()
                case .stats: StatsView()
                case .showcase: ShowcaseView()
                case .settings: SettingsView()
                }
            }
            .athlosPage()
            .toolbarBackground(Theme.canvas, for: .windowToolbar)
        }
        .tint(Theme.accent)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.line))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if model.celebrating { CelebrationView().allowsHitTesting(false) }
        }
        // Shared sheets
        .sheet(isPresented: $model.showQuickPicker) { QuickPickerView().athlosPage().tint(Theme.accent) }
        .sheet(isPresented: $model.showStopSheet) { StopSessionSheet().athlosPage().tint(Theme.accent) }
        .sheet(item: $model.projectEditor) { req in ProjectEditorView(request: req).athlosPage().tint(Theme.accent) }
        .sheet(item: $model.newTopicRequest) { req in NewTopicSheet(request: req).athlosPage().tint(Theme.accent) }
        .sheet(item: $model.planEditor) { req in PlanEditorView(request: req).athlosPage().tint(Theme.accent) }
        // Unfinished session
        .alert("Unfinished session", isPresented: Binding(get: { model.recovery != nil }, set: { _ in })) {
            Button("Continue") { model.resolveRecovery(.continue) }
            if let alive = model.recovery?.lastAlive {
                Button("End at last activity (\(Fmt.time(alive)))") { model.resolveRecovery(.finishAtLastAlive) }
            }
            Button("Stop now") { model.resolveRecovery(.finishNow) }
        } message: {
            if let r = model.recovery {
                Text("\(model.store.pathString(projectID: model.store.entry(r.entryID)?.projectID, topicID: model.store.entry(r.entryID)?.topicID)) — an entry that started on \(Fmt.dateTime(r.startedAt)) was never closed. Continue, including the time since the app closed?")
            }
        }
        // Idle detection
        .alert("Are you still working?", isPresented: Binding(get: { model.idlePrompt != nil }, set: { _ in })) {
            Button("Discard idle time", role: .destructive) { model.resolveIdle(discard: true) }
            Button("Keep the time") { model.resolveIdle(discard: false) }
        } message: {
            if let p = model.idlePrompt {
                Text("No keyboard or mouse activity since \(Fmt.time(p.idleSince)).")
            }
        }
        .onAppear {
            model.openMainWindow = { [openWindow] in openWindow(id: "main") }
        }
    }

}

/// Sidebar: logo + wordmark, page buttons, live status at the bottom.
/// Plain buttons instead of a List so the marble style (and the selected pill) is fully ours.
private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AthlosBrand(logoSize: 36)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 18)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(Route.allCases, id: \.self) { r in
                        SidebarRow(route: r, selected: model.route == r, badge: badge(for: r)) { model.route = r }
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.never)
            SidebarStatus()
                .padding(12)
                .athlosCard(radius: 12)
                .padding(10)
        }
        .background(Theme.sidebar)
        .toolbarBackground(Theme.sidebar, for: .windowToolbar)
    }

    private func badge(for r: Route) -> Int? {
        guard r == .showcase else { return nil }
        let c = model.store.projects(status: .completed).count
        return c > 0 ? c : nil
    }
}

private struct SidebarRow: View {
    let route: Route
    let selected: Bool
    let badge: Int?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: route.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? Theme.goldText : Theme.inkSecondary)
                    .frame(width: 20)
                Text(route.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink.opacity(0.82))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                if let badge {
                    Text(verbatim: "\(badge)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.goldText)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Theme.goldSoft, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line))
                        .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.ink.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small live status under the sidebar (active topic + daily goal bar).
private struct SidebarStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.timer.phase != .idle {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.timer.phase == .working ? Theme.gold : model.timer.phase == .onBreak ? Theme.rest : Theme.paused)
                        .frame(width: 7, height: 7)
                    Text(model.activePath.last ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(model.menuBarTitle.dropFirst(2))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            GoalBarView(compact: true)
        }
    }
}

/// "What did you do?" note when stopping a session.
struct StopSessionSheet: View {
    @Environment(AppModel.self) private var model
    @State private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stop session").font(Theme.display(24))
            Text("\(model.activePath.joined(separator: " › ")) · \(Fmt.hm(model.sessionWork))")
                .foregroundStyle(.secondary)
            Text("What did you do? (optional)").font(.headline)
            TextEditor(text: $note)
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                .focused($focused)
            HStack {
                Button("Cancel", role: .cancel) { model.showStopSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Stop without note") { model.finishStop(note: nil) }
                Button("Save and stop") { model.finishStop(note: note) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .background(Theme.canvas)
        .frame(width: 440)
        .onAppear { focused = true }
    }
}

/// A simple celebration: colorful particles flying up.
struct CelebrationView: View {
    @State private var animate = false
    private let pieces: [(x: CGFloat, delay: Double, color: Color, symbol: String)] = (0..<36).map { i in
        let colors: [Color] = [Theme.goldBright, Theme.gold, Theme.goldDeep, Theme.rest, Color(hex: "#FBF6EC"), Theme.goldBright]
        let symbols = ["star.fill", "sparkle", "circle.fill", "seal.fill"]
        return (CGFloat.random(in: 0.05...0.95), Double.random(in: 0...0.6), colors[i % colors.count], symbols[i % symbols.count])
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces.indices, id: \.self) { i in
                    let p = pieces[i]
                    Image(systemName: p.symbol)
                        .font(.system(size: CGFloat(10 + (i % 4) * 5)))
                        .foregroundStyle(p.color)
                        .position(x: p.x * geo.size.width, y: animate ? -40 : geo.size.height + 40)
                        .rotationEffect(.degrees(animate ? Double(i * 40) : 0))
                        .opacity(animate ? 0 : 1)
                        .animation(.easeOut(duration: 2.6).delay(p.delay), value: animate)
                }
                VStack(spacing: 12) {
                    AthlosLogo(size: 72)
                    Text("Daily goal reached!")
                        .font(Theme.display(30, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(28)
                .athlosCard(radius: 24)
                .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
                    .scaleEffect(animate ? 1 : 0.6)
                    .opacity(animate ? 1 : 0)
                    .animation(.spring(duration: 0.5, bounce: 0.4), value: animate)
            }
        }
        .onAppear { animate = true }
        .transition(.opacity)
    }
}
