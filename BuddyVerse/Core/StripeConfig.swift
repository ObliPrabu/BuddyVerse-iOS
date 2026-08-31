import Foundation

// Mirrors StripeConfig.kt.
enum StripeConfig {
    // One-time, single-game unlock.
    static let expeditionPaymentLinkURL = "https://buy.stripe.com/test_cNidRa61hcuF6lm4N74Ni00"

    // Recurring subscriptions for unlimited premium game access.
    static let subscriptionMonthlyPaymentLinkURL = "https://buy.stripe.com/test_5kQ5kEgFk8UW76cgTFbAs00"
    static let subscriptionYearlyPaymentLinkURL = "https://buy.stripe.com/test_fZu14o0Gmgno3U05aXbAs02"

    // Both Payment Links' "After payment" redirect (set in the Stripe
    // Dashboard) points at this real site - PaymentWebView watches for its
    // embedded WKWebView navigating here as the signal that checkout is done.
    static let paymentSuccessHost = "ambitious-desert-027b7dd0f.7.azurestaticapps.net"

    static func paymentLink(for source: String) -> URL {
        let urlString: String
        switch source {
        case "SUB_MONTHLY": urlString = subscriptionMonthlyPaymentLinkURL
        case "SUB_YEARLY": urlString = subscriptionYearlyPaymentLinkURL
        default: urlString = expeditionPaymentLinkURL
        }
        return URL(string: urlString)!
    }
}

// Mirrors PendingPayment.kt: holds which game/mode a Stripe payment was
// started for while the user is off in Stripe checkout. In-memory only -
// this only needs to survive a few seconds in the same app session.
enum PendingPayment {
    // Only ever set/read on the main thread (LobbyView/PaymentWebView, both
    // MainActor-isolated SwiftUI code) - see ThemeManager for the same pattern.
    nonisolated(unsafe) static var gameType: String?
    nonisolated(unsafe) static var source: String?
}
