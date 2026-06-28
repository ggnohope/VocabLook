import Foundation
import UserNotifications
import AppKit

/// Schedules one repeating daily local notification at the user's chosen time.
final class Reminder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminder()
    private let center = UNUserNotificationCenter.current()
    private let identifier = "vocablook.daily"

    func configure() {
        center.delegate = self
        Permissions.requestNotifications { [weak self] granted in
            if granted { self?.reschedule() }
        }
    }

    /// Re-create the daily trigger from current settings + due count.
    func reschedule() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let due = (try? Store.shared.dueCount(now: Date())) ?? 0
        let content = UNMutableNotificationContent()
        content.title = "VocabLook"
        content.body = due > 0
            ? "\(due) words ready to review — keep your 🔥 \(Settings.streakCount)-day streak."
            : "Time for today's vocabulary review."
        content.sound = .default

        var date = DateComponents()
        date.hour = Settings.reminderHour
        date.minute = Settings.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// Show the banner even when (rarely) our app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Tapping the notification opens the review window (on the current Space).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            WindowManager.shared.showReview(scope: .due)
        }
        completionHandler()
    }
}
