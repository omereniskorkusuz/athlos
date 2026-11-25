import Foundation
import UserNotifications

/// Local notifications (break time, break over, idle, goal reached).
/// Notification actions (Skip / Snooze / Continue) are passed to the app through `onAction`.
@MainActor
final class NotificationService: NSObject {
    enum Action: String {
        case skipBreak = "SKIP_BREAK"
        case snoozeBreak = "SNOOZE_BREAK"
        case resumeWork = "RESUME_WORK"
        case endBreakNow = "END_BREAK"
    }

    private enum Category: String {
        case breakStarted = "BREAK_STARTED"
        case breakEnded = "BREAK_ENDED"
        case info = "INFO"
    }

    var onAction: ((Action) -> Void)?

    /// UNUserNotificationCenter is unavailable when running outside a bundle (e.g. `swift run`).
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }
    private var center: UNUserNotificationCenter? { available ? .current() : nil }

    func setup() {
        guard let center else { return }
        center.delegate = self
        let skip = UNNotificationAction(identifier: Action.skipBreak.rawValue, title: String(localized: "Skip break"))
        let snooze = UNNotificationAction(identifier: Action.snoozeBreak.rawValue, title: String(localized: "Snooze 5 min"))
        let resume = UNNotificationAction(identifier: Action.resumeWork.rawValue, title: String(localized: "Continue"), options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.breakStarted.rawValue, actions: [skip, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.breakEnded.rawValue, actions: [resume], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.info.rawValue, actions: [], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func breakStarted(workMinutes: Int, breakMinutes: Int) {
        post(id: "break", title: String(localized: "Time for a break ☕️"),
             body: String(localized: "You worked \(workMinutes) min. A \(breakMinutes)-min break has started."),
             category: .breakStarted)
    }

    func breakEnded() {
        post(id: "break", title: String(localized: "Break is over"),
             body: String(localized: "Ready to continue? 💪"), category: .breakEnded)
    }

    func idle(minutes: Int) {
        post(id: "idle", title: String(localized: "Are you still working?"),
             body: String(localized: "No keyboard or mouse activity for \(minutes) minutes."), category: .info)
    }

    func goalReached(hours: String) {
        post(id: "goal", title: String(localized: "Daily goal reached! 🎉"),
             body: String(localized: "You worked \(hours) today. Great job!"), category: .info)
    }

    func clearBreakNotifications() {
        center?.removeDeliveredNotifications(withIdentifiers: ["break"])
    }

    private func post(id: String, title: String, body: String, category: Category) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Show notifications even while the app is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        Task { @MainActor in
            if let action = Action(rawValue: id) {
                self.onAction?(action)
            } else if id == UNNotificationDefaultActionIdentifier, category == Category.breakEnded.rawValue {
                self.onAction?(.resumeWork)
            }
        }
        completionHandler()
    }
}
