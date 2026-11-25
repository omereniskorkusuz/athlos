import SwiftUI
import AthlosCore

/// Main window: sidebar + selected page. Shared sheets and alerts live here.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        // A fixed-width icon rail + the page. (No NavigationSplitView: its sidebar can't be made this narrow.)
        // The rail's color runs up under the title bar, so the traffic lights sit on the rail.
        HStack(spacing: 0) {
            IconRail()
                .frame(width: IconRail.width)
            Group {
                switch model.route {
                case .timer: TimerView()
                case .projects: ProjectsView()
                case .stats: StatsView()
                case .showcase: ShowcaseView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .athlosPage()
        }
        .background {
            HStack(spacing: 0) {
                Theme.rail.frame(width: IconRail.width)
                Theme.line.frame(width: 1)
                Theme.canvas
            }
            .ignoresSafeArea()
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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

/// Sidebar as a narrow icon rail: logo, page buttons (tooltips), Settings and a daily-goal ring at the bottom.
/// Plain buttons instead of a List so the style (selected tile + star mark) is fully ours.
private struct IconRail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            AthlosLogo(size: 36)
                .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                .padding(.top, 6)
                .padding(.bottom, 10)
            ForEach(Route.allCases.filter { $0 != .settings }, id: \.self) { r in
                RailButton(route: r, selected: model.route == r, badge: badge(for: r)) { model.route = r }
            }
            Spacer(minLength: 8)
            RailButton(route: .settings, selected: model.route == .settings, badge: nil) { model.route = .settings }
            RailGoalRing()
                .padding(.top, 4)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Wide enough for the window's traffic lights.
    static let width: CGFloat = 76

    private func badge(for r: Route) -> Int? {
        guard r == .showcase else { return nil }
        let c = model.store.projects(status: .completed).count
        return c > 0 ? c : nil
    }
}

private struct RailButton: View {
    let route: Route
    let selected: Bool
    let badge: Int?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: route.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(selected ? Theme.brandText : (hovering ? Theme.ink : Theme.inkSecondary))
                .frame(width: 42, height: 42)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.brandSoft)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ink.opacity(0.06))
                    }
                }
                .overlay(alignment: .leading) {
                    // The logo's four-pointed star marks the current page.
                    if selected {
                        StarMark().fill(Theme.star).frame(width: 9, height: 9).offset(x: -6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(verbatim: "\(badge)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Theme.onPrimary)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Theme.brand, in: Capsule())
                            .offset(x: 2, y: -2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text(route.title))
        .accessibilityLabel(Text(route.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Four-pointed star from the logo.
struct StarMark: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), w = r.width / 2, h = r.height / 2, k: CGFloat = 0.19
        var p = Path()
        p.addLines([CGPoint(x: c.x, y: c.y - h), CGPoint(x: c.x + w * k, y: c.y - h * k), CGPoint(x: c.x + w, y: c.y),
                    CGPoint(x: c.x + w * k, y: c.y + h * k), CGPoint(x: c.x, y: c.y + h), CGPoint(x: c.x - w * k, y: c.y + h * k),
                    CGPoint(x: c.x - w, y: c.y), CGPoint(x: c.x - w * k, y: c.y - h * k)])
        p.closeSubpath()
        return p
    }
}

/// Small daily-goal ring at the bottom of the rail; shows the running time on hover.
private struct RailGoalRing: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.todayWork / max(model.dailyGoal, 1)
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 3)
            Circle().trim(from: 0, to: min(progress, 1))
                .stroke(progress >= 1 ? Theme.brandDeep : Theme.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if model.timer.phase != .idle {
                Circle()
                    .fill(model.timer.phase == .working ? Theme.brand : model.timer.phase == .onBreak ? Theme.rest : Theme.paused)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 30, height: 30)
        .help(Text("Daily goal: \(Fmt.hm(model.todayWork)) / \(Fmt.hm(model.dailyGoal))"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily goal")
        .accessibilityValue(Text("\(Fmt.spoken(model.todayWork)) / \(Fmt.spoken(model.dailyGoal))"))
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
        let colors: [Color] = [Theme.brandBright, Theme.brand, Theme.brandDeep, Theme.rest, Theme.star, Theme.brandBright]
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
