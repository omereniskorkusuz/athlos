import SwiftUI
import AthlosCore

/// Main window: sidebar + selected page. Shared sheets and alerts live here.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.sidebarSelection) {
                Section {
                    // id: \.self → the rows' selection ID is the Route itself.
                    // (Route is Identifiable, so the default ID was its String rawValue; the List could not turn that
                    // into the Route? selection and sent nil → the sidebar couldn't be clicked.)
                    ForEach(Route.allCases, id: \.self) { r in
                        Label(r.title, systemImage: r.symbol)
                            .badge(badge(for: r))
                            .tag(r)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) {
                SidebarStatus()
                    .padding(10)
            }
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
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 4, y: 2)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if model.celebrating { CelebrationView().allowsHitTesting(false) }
        }
        // Shared sheets
        .sheet(isPresented: $model.showQuickPicker) { QuickPickerView() }
        .sheet(isPresented: $model.showStopSheet) { StopSessionSheet() }
        .sheet(item: $model.projectEditor) { req in ProjectEditorView(request: req) }
        .sheet(item: $model.newTopicRequest) { req in NewTopicSheet(request: req) }
        .sheet(item: $model.planEditor) { req in PlanEditorView(request: req) }
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

    private func badge(for r: Route) -> Text? {
        switch r {
        case .showcase:
            let c = model.store.projects(status: .completed).count
            return c > 0 ? Text("\(c)") : nil
        default: return nil
        }
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
                        .fill(model.timer.phase == .working ? Color.green : model.timer.phase == .onBreak ? .orange : .secondary)
                        .frame(width: 7, height: 7)
                    Text(model.activePath.last ?? "")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(model.menuBarTitle.dropFirst(2))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
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
            Text("Stop session").font(.title2.bold())
            Text("\(model.activePath.joined(separator: " › ")) · \(Fmt.hm(model.sessionWork))")
                .foregroundStyle(.secondary)
            Text("What did you do? (optional)").font(.headline)
            TextEditor(text: $note)
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
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
        .frame(width: 440)
        .onAppear { focused = true }
    }
}

/// A simple celebration: colorful particles flying up.
struct CelebrationView: View {
    @State private var animate = false
    private let pieces: [(x: CGFloat, delay: Double, color: Color, symbol: String)] = (0..<36).map { i in
        let colors: [Color] = [.goalGold, .orange, .pink, .green, .blue, .purple]
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
                Text("🎉 Daily goal reached!")
                    .font(.largeTitle.bold())
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .scaleEffect(animate ? 1 : 0.6)
                    .opacity(animate ? 1 : 0)
                    .animation(.spring(duration: 0.5, bounce: 0.4), value: animate)
            }
        }
        .onAppear { animate = true }
        .transition(.opacity)
    }
}
