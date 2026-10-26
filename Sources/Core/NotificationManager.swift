import Foundation
import UserNotifications

/// System notifications for interval changes, with quick actions.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let identifier = "focus-timer"

    func setUp() {
        center.delegate = self
        let start = UNNotificationAction(identifier: "start", title: String(localized: "Start"), options: [])
        let skip = UNNotificationAction(identifier: "skip", title: String(localized: "Skip"), options: [])
        let extend = UNNotificationAction(identifier: "extend", title: String(localized: "+1 Minute"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "waiting", actions: [start, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: "running", actions: [skip, extend], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    func handle(_ event: TimerEvent) {
        let settings = AppSettings.shared
        let session = SessionManager.shared
        guard settings.notificationsEnabled else { return }
        let minutes = Int((session.duration / 60).rounded())

        switch event {
        case .pomodoroStarted:
            let body = String(localized: "Focus for \(minutes) minutes")
            post(String(localized: "Pomodoro"), session.task.isEmpty ? body : "\(body) — \(session.task)", category: "running")
        case .breakStarted:
            post(session.phase == .longBreak ? String(localized: "Long Break") : String(localized: "Take a Break"),
                 String(localized: "You have \(minutes) minutes to rest"), category: "running")
        case .waiting:
            post(session.phase.isBreak ? String(localized: "Pomodoro finished") : String(localized: "Break is over"),
                 session.phase.isBreak ? String(localized: "Ready to start a \(session.phase.title)?")
                                       : session.waitsForActivity
                                           ? String(localized: "The pomodoro starts as soon as you move the mouse or type.")
                                           : String(localized: "Ready to focus again?"),
                 category: "waiting")
        case .aboutToEnd:
            post(String(localized: "\(session.phase.title) is about to end"),
                 String(localized: "\(settings.announcementLeadTime) seconds remaining"), category: "running")
        case .stopped:
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        default:
            break
        }
    }

    private func post(_ title: String, _ body: String, category: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let session = SessionManager.shared
                switch action {
                case "start": session.start()
                case "skip": session.skip()
                case "extend": session.extend(by: 60)
                default: AppController.shared.showMainWindow()
                }
            }
        }
        completionHandler()
    }
}
