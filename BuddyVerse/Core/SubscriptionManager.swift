import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Tracks whether this account has an active $4/month or $40/year premium
/// subscription, so every premium expedition game can skip straight past
/// LobbyView's paywall the same way a free game does. Direct Swift port of
/// SubscriptionManager.kt.
///
/// Keyed by a real Firebase email/password account UID (see AuthManager),
/// not the per-device anonymous UID InternetConnectionManager uses for
/// multiplayer - LobbyView now requires signing in/up via AccountView before
/// any payment goes through, specifically so this entitlement is tied to
/// something recoverable on another device instead of being lost on
/// reinstall. isSubscribed()/markSubscribed() are only ever meaningfully
/// called once that login has happened; if nobody's logged in there's
/// nothing to look up, so isSubscribed() just reports false.
///
/// There's no backend server in this app, so this deliberately does the
/// simplest thing that can be built with just the client + Firestore: after
/// a subscription Payment Link checkout succeeds, this writes
/// `subscriptions/{uid}` = `{active: true, plan: "monthly"|"yearly"}` to
/// Firestore. isSubscribed() reads that doc.
///
/// Known gap: this only ever gets SET to true, never automatically back to
/// false. Stripe knows when a subscription is cancelled or a renewal payment
/// fails, but telling this app about that requires a server receiving Stripe
/// webhooks, which doesn't exist here. Until one does, a subscriber keeps
/// access even after cancelling/lapsing - a deliberate, known trade-off for
/// launching without backend infrastructure, not an oversight.
final class SubscriptionManager {
    nonisolated(unsafe) static let shared = SubscriptionManager()
    private init() {}

    private var db: Firestore { Firestore.firestore() }
    private var cachedActive: Bool?

    func clearCache() {
        cachedActive = nil
    }

    /// Checks (and caches for the rest of this app session) whether this account is subscribed.
    func isSubscribed(_ onResult: @escaping (Bool) -> Void) {
        if let cachedActive {
            onResult(cachedActive)
            return
        }

        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            onResult(false)
            return
        }

        db.collection("subscriptions").document(user.uid).getDocument { [weak self] snapshot, error in
            guard let self else { return }
            let active = (snapshot?.get("active") as? Bool) == true
            if error != nil {
                print("SubscriptionManager: couldn't read subscription status: \(error!)")
                onResult(false)
                return
            }
            self.cachedActive = active
            onResult(active)
        }
    }

    /// Call once a subscription Payment Link checkout succeeds. Requires AuthManager.isLoggedIn().
    func markSubscribed(_ plan: String, onDone: @escaping () -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            onDone()
            return
        }
        let data: [String: Any] = ["active": true, "plan": plan]
        db.collection("subscriptions").document(uid).setData(data) { [weak self] _ in
            self?.cachedActive = true
            onDone()
        }
    }
}
