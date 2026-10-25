import Foundation
import FirebaseFirestore

/// iOS counterpart of Android's background feedback check. iOS does not let
/// an app poll in the background without a push server, so this runs each
/// time the app comes to the foreground: if the admin account is signed in
/// and feedback or reports arrived since the admin was last told, it shows a
/// local notification that summarizes them.
enum AdminFeedbackChecker {
    static func checkNow() {
        guard AuthManager.isAdmin() else { return }
        let since = AdminNotificationTracker.lastNotifiedAt()
        let db = Firestore.firestore()
        var feedbackDocs: [QueryDocumentSnapshot] = []
        var reportDocs: [QueryDocumentSnapshot] = []
        let group = DispatchGroup()
        group.enter()
        db.collection("feedback").whereField("createdAt", isGreaterThan: since).getDocuments { snap, _ in
            feedbackDocs = snap?.documents ?? []
            group.leave()
        }
        group.enter()
        db.collection("reports").whereField("createdAt", isGreaterThan: since).getDocuments { snap, _ in
            reportDocs = snap?.documents ?? []
            group.leave()
        }
        group.notify(queue: .main) {
            let total = feedbackDocs.count + reportDocs.count
            guard total > 0 else { return }
            let newest = (feedbackDocs + reportDocs)
                .compactMap { ($0.data()["createdAt"] as? Timestamp)?.dateValue().timeIntervalSince1970 }
                .max().map { $0 * 1000 } ?? Date().timeIntervalSince1970 * 1000
            AdminNotificationTracker.markNotifiedUpTo(millis: newest)
            LocalNotificationManager.shared.notifyNewFeedback(feedback: feedbackDocs.count, reports: reportDocs.count)
        }
    }
}
