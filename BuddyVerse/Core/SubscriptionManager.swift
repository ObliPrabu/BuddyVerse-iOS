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
    private var cachedUnlockedExpeditions: Set<String> = []

    func clearCache() {
        cachedActive = nil
        cachedUnlockedExpeditions = []
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
            self?.logPurchase(plan: plan, gameType: nil, amountCents: plan == "yearly" ? 4000 : 400)
            onDone()
        }
    }

    /// Checks (and caches for the rest of this app session) whether this
    /// account already paid the one-time 50-cent unlock for this specific
    /// premium game. Unlike a subscription, this never expires/lapses - it's
    /// a permanent per-game entitlement, stored as one boolean field per
    /// gameType on a single `expeditionUnlocks/{uid}` doc rather than one doc
    /// per game, so checking/granting access never needs more than one round trip.
    func isExpeditionUnlocked(gameType: String, _ onResult: @escaping (Bool) -> Void) {
        if cachedUnlockedExpeditions.contains(gameType) {
            onResult(true)
            return
        }

        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            onResult(false)
            return
        }

        db.collection("expeditionUnlocks").document(user.uid).getDocument { [weak self] snapshot, error in
            guard let self else { return }
            if error != nil {
                print("SubscriptionManager: couldn't read expedition unlock status: \(error!)")
                onResult(false)
                return
            }
            let unlocked = (snapshot?.get(gameType) as? Bool) == true
            if unlocked { self.cachedUnlockedExpeditions.insert(gameType) }
            onResult(unlocked)
        }
    }

    /// Call once a one-time EXPEDITION Payment Link checkout succeeds for a
    /// specific game. Requires AuthManager.isLoggedIn().
    func markExpeditionUnlocked(gameType: String, onDone: @escaping () -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            onDone()
            return
        }
        db.collection("expeditionUnlocks").document(uid).setData([gameType: true], merge: true) { [weak self] _ in
            self?.cachedUnlockedExpeditions.insert(gameType)
            self?.logPurchase(plan: "expedition", gameType: gameType, amountCents: 50)
            onDone()
        }
    }

    /// A self-reported revenue log, written by this client the instant it
    /// believes a payment succeeded (right after Stripe's own checkout
    /// redirect confirms it) - NOT Stripe's authoritative ledger. There's no
    /// backend here to receive real Stripe webhooks, so this is the only
    /// admin-visible revenue signal available; it won't reflect refunds or
    /// chargebacks, and amounts are the app's own known price tiers, not
    /// anything read back from Stripe. Write-only from here - only the admin
    /// account can read this collection back (see Firestore rules).
    private func logPurchase(plan: String, gameType: String?, amountCents: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = [
            "uid": uid,
            "plan": plan,
            "amountCents": amountCents,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let gameType { data["gameType"] = gameType }
        db.collection("purchases").addDocument(data: data)
    }
}
