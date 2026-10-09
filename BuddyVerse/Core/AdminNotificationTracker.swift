import Foundation
import FirebaseFirestore

/// Tracks when the admin last viewed the Admin Dashboard, purely on-device
/// (UserDefaults) - lets AdminDashboardView highlight which feedback/report
/// rows arrived since the last visit. Mirrors Android's
/// AdminNotificationTracker.kt.
enum AdminNotificationTracker {
    private static let key = "admin_notifications_last_viewed_millis"

    /// The first call ever (no stored value yet) seeds itself to "now"
    /// rather than epoch zero - otherwise every piece of feedback/report
    /// ever submitted before this feature shipped would count as "new" the
    /// first time someone opens the app after updating.
    static func lastViewedAt() -> Timestamp {
        let defaults = UserDefaults.standard
        var millis = defaults.double(forKey: key)
        if millis == 0 {
            millis = Date().timeIntervalSince1970 * 1000
            defaults.set(millis, forKey: key)
        }
        return Timestamp(seconds: Int64(millis / 1000), nanoseconds: Int32((millis.truncatingRemainder(dividingBy: 1000)) * 1_000_000))
    }

    static func markViewedNow() {
        UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: key)
    }
}
