@preconcurrency import UserNotifications

/// Fires a local (on-device, no backend/APNs involved) notification when the
/// admin publishes a new version from AdminDashboardView's Updates section -
/// a quick confirmation, right on the admin's own device, that
/// AppFeedbackService's write to appConfig/latest actually went through,
/// echoing back the same version/"what's new" message just published.
final class LocalNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    nonisolated(unsafe) static let shared = LocalNotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func notifyVersionPublished(version: String, message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Version \(version) Published"
            content.body = message.isEmpty ? "No \"what's new\" message was entered." : message
            content.sound = .default
            // Without this, a Focus mode can silently queue the notification
            // instead of showing it right away (confirmed on-device: it sat
            // queued through ~20 publishes and only delivered once Focus was
            // turned off) - .timeSensitive is the level Apple intends for
            // exactly this "the user just took an action, tell them now" case.
            // UNNotificationInterruptionLevel itself is iOS 15+ - this app's
            // floor is 14.0, so this quietly no-ops (falls back to the
            // default .active level) on anything older.
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            center.add(request)
        }
    }

    // The admin is looking right at the Admin Dashboard when they tap
    // Publish, so the notification fires while the app is in the
    // foreground - without this delegate method, foreground local
    // notifications are silently swallowed instead of showing a banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
