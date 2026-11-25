import Foundation
import WidgetKit
import AthlosCore

/// Bridge between the app and its macOS widgets.
/// - Writes the widget snapshot and reloads widgets when the state changes.
/// - Applies commands coming from widget buttons (Darwin notification + command file).
@MainActor
final class WidgetBridge {
    private weak var model: AppModel?
    private var last: WidgetSnapshot?
    private var lastWrite = Date.distantPast

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        // Command signal from the widget (a sandboxed extension may post Darwin notifications).
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let bridge = Unmanaged<WidgetBridge>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { bridge.processCommands() }
            }
        }, WidgetSnapshot.commandNotification as CFString, nil, .deliverImmediately)
        // Recent commands left while the app was closed
        processCommands()
        update(force: true)
    }

    /// Called on every tick; writes only if something visible changed (or 10 minutes passed).
    func update(force: Bool = false) {
        guard let model else { return }
        let snap = WidgetSnapshot.make(store: model.store, timer: model.timer, now: Date())
        if !force, let last, last.isVisuallyEqual(to: snap), Date().timeIntervalSince(lastWrite) < 600 { return }
        do {
            try snap.save()
            last = snap
            lastWrite = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            NSLog("Athlos: could not write widget snapshot: \(error.localizedDescription)")
        }
    }

    /// Applies commands from widget buttons.
    func processCommands() {
        guard let model else { return }
        let commands = WidgetCommand.drain()
        guard !commands.isEmpty else { return }
        for cmd in commands {
            switch cmd {
            case .toggle:
                if !model.timer.toggle() {
                    // While idle: start the most recent topic; otherwise open the app and show the picker.
                    if let recent = model.store.recentTargets(limit: 1).first {
                        model.start(projectID: recent.projectID, topicID: recent.topicID)
                    } else {
                        model.openQuickPicker()
                        model.bringToFront()
                    }
                }
            case .stop:
                // No note prompt when stopping from the widget (the app shouldn't come to the front).
                model.timer.stop()
            case .startBreak:
                model.timer.startBreak()
            case .skipBreak:
                model.timer.skipBreak()
            }
        }
        model.now = Date()
        update(force: true)
    }
}
