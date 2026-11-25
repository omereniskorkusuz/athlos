import SwiftUI
import Carbon.HIToolbox
import AthlosCore

@main
struct AthlosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Athlos", id: "main") {
            ContentView()
                .environment(model)
                .environment(\.locale, Fmt.locale)
                .frame(minWidth: 820, minHeight: 560)
                .task { appDelegate.model = model }
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified)
        .commands { AthlosCommands(model: model) }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
                .environment(\.locale, Fmt.locale)
        } label: {
            MenuBarLabel(model: model)
                // The menu bar label appears on every launch: even if the main window never opens,
                // start the model and register the open-window action.
                .task { appDelegate.model = model }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(\.locale, Fmt.locale)
                .frame(width: 560, height: 640)
        }
    }
}

/// Menu bar label: an icon while idle, the time while running.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.timer.phase == .idle {
                Image(systemName: "timer")
                    .accessibilityLabel("Athlos")
            } else {
                Text(model.menuBarTitle)
                    .monospacedDigit()
                    .accessibilityLabel(Text("Athlos timer \(Fmt.spoken(model.displaySeconds))"))
            }
        }
        .onAppear {
            if model.openMainWindow == nil {
                model.openMainWindow = { [openWindow] in openWindow(id: "main") }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var model: AppModel? {
        didSet { if oldValue == nil { model?.launch(); flushPendingURLs() } }
    }

    /// Links can arrive before the app has finished launching; they are handled once the model is ready.
    @MainActor private var pendingURLs: [URL] = []

    @MainActor
    func applicationWillFinishLaunching(_ notification: Notification) {
        // athlos:// links (clicking a widget). To keep SwiftUI from opening a new window,
        // we handle the Apple Event directly.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @MainActor @objc
    func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s) else { return }
        if let model { model.handle(url: url) } else { pendingURLs.append(url) }
    }

    @MainActor
    func flushPendingURLs() {
        guard let model else { return }
        pendingURLs.forEach { model.handle(url: $0) }
        pendingURLs.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keeps running in the menu bar even when the window is closed
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model?.openMainWindow?() } // Clicking the Dock icon opens the window if none is open
        return true
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        // The running entry stays open (the next launch asks "continue / end here");
        // only the last "alive" moment is saved.
        model?.timer.heartbeat()
    }
}

/// Menu commands and keyboard shortcuts.
struct AthlosCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") { model.newProject(); model.bringToFront() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Subtopic") { model.newTopic(); model.bringToFront() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Timer") {
            Button(model.timer.phase == .working ? "Pause" : "Start / Resume") { model.toggleOrPick() }
                .keyboardShortcut(.space, modifiers: [.control, .option])
            Button("Choose Topic…") { model.route = .timer; model.openQuickPicker(switchOnly: model.timer.phase != .idle) }
                .keyboardShortcut("k", modifiers: .command)
            Button("Stop") { model.requestStop() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.timer.phase == .idle)
            Divider()
            Button("Start Break") { model.timer.startBreak(); model.now = Date() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!(model.timer.phase == .working || model.timer.phase == .paused))
            Button("Skip Break") { model.timer.skipBreak() }
                .disabled(model.timer.phase != .onBreak)
            Button("Snooze Break 5 min") { model.timer.snoozeBreak() }
                .disabled(model.timer.phase != .onBreak)
        }
        CommandGroup(after: .sidebar) {
            Toggle("Desktop Widget", isOn: Binding(get: { model.desktopWidgetVisible }, set: { model.setDesktopWidget(visible: $0) }))
                .keyboardShortcut("w", modifiers: [.command, .option])
            Divider()
            ForEach(Array(Route.allCases.enumerated()), id: \.element) { i, r in
                Button(r.title) { model.route = r; model.bringToFront() }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
    }
}
