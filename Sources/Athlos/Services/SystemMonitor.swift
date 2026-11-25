import AppKit
import CoreGraphics

/// Watches sleep / wake / screen lock events and idle time.
@MainActor
final class SystemMonitor {
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    private var tokens: [NSObjectProtocol] = []

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()

        tokens.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSleep?() }
        })
        tokens.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake?() }
        })
        // Screen lock is handled like sleep (pause / keep counting, depending on the setting).
        tokens.append(dist.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSleep?() }
        })
        tokens.append(dist.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake?() }
        })
    }

    /// Seconds since the last keyboard/mouse event (needs no permission).
    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
