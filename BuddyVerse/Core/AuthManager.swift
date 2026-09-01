import Foundation
import FirebaseAuth

/// Thin wrapper around Firebase email/password auth. Direct Swift port of
/// AuthManager.kt. Exists so a premium purchase (one-time or subscription)
/// can be tied to a real, recoverable account instead of
/// SubscriptionManager's old per-device anonymous UID - logging back into
/// the same account on another device (or after a reinstall) now brings any
/// subscription back with it, since it's keyed by this real UID instead.
/// InternetConnectionManager's anonymous auth for multiplayer is untouched
/// and stays completely separate from this.
enum AuthManager {
    /// True only for a real signed-up account. An anonymous session (the
    /// kind InternetConnectionManager/old SubscriptionManager used) doesn't
    /// count, since it isn't recoverable on another device.
    static func isLoggedIn() -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        return !user.isAnonymous
    }

    static func currentEmail() -> String? {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { return nil }
        return user.email
    }

    // Just an email address, not a secret - the actual gate is a real signed-in
    // Firebase session for this exact account, not knowledge of this string.
    private static let adminEmail = "mithran.obliprabu@gmail.com"

    /// True only when the currently signed-in account is the one designated
    /// admin account - used to gate the Welcome screen's admin dashboard
    /// entry point so it's invisible to everyone else.
    static func isAdmin() -> Bool {
        currentEmail()?.lowercased() == adminEmail
    }

    static func signUp(email: String, password: String, onResult: @escaping (_ success: Bool, _ error: String?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { _, error in
            onResult(error == nil, error?.localizedDescription)
        }
    }

    static func logIn(email: String, password: String, onResult: @escaping (_ success: Bool, _ error: String?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            onResult(error == nil, error?.localizedDescription)
        }
    }

    static func logOut() {
        try? Auth.auth().signOut()
        SubscriptionManager.shared.clearCache()
    }
}
