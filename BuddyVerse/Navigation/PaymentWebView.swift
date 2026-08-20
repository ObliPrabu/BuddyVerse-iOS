import SwiftUI

/// Mirrors PaymentWebViewActivity.kt/activity_payment_webview.xml: loads
/// Stripe checkout in an embedded WebView right inside the app (not an
/// external browser/Custom Tab), so checkout feels like it never leaves
/// BuddyVerse. Picking the flow back up doesn't need a deep link - it just
/// watches the WebView's own navigation for it reaching
/// StripeConfig.paymentSuccessHost (the real website's Stripe "After payment"
/// redirect) and treats that as done. Only the surrounding chrome (back
/// button placement/style, error state copy) mirrors Android here - none of
/// the WKWebView/Stripe navigation-watching logic below is touched.
struct PaymentWebView: View {
    let gameType: String
    let premiumSource: String
    let onSucceeded: (GameSelection) -> Void

    @State private var showError = false
    @State private var reloadToken = UUID()
    @EnvironmentObject private var router: Router

    private var checkoutURL: URL { StripeConfig.paymentLink(for: premiumSource) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !showError {
                TrustedWebView(
                    url: checkoutURL,
                    allowedHosts: { host in
                        host == StripeConfig.paymentSuccessHost
                            || host.hasSuffix("stripe.com")
                            || host.hasSuffix("stripe.network")
                    },
                    onNavigate: { url in
                        guard url.host == StripeConfig.paymentSuccessHost else { return false }
                        onPaymentSucceeded()
                        return true
                    },
                    onLoadError: { showError = true }
                )
                .id(reloadToken)
                .ignoresSafeArea()
            } else {
                errorState
            }

            // Mirrors activity_payment_webview.xml's btnCancelPayment: a
            // white pill pinned top-left with a drop shadow
            // (android:elevation="6dp"), labeled "Back" - not a system nav bar.
            Button("Back") { router.pop() }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: 0x333333))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .buttonStyle(.plain)
                .padding(16)
        }
        .navigationBarHidden(true)
        .onAppear {
            PendingPayment.gameType = gameType
            PendingPayment.source = premiumSource
        }
    }

    private var errorState: some View {
        VStack(spacing: 16) {
            Text("Couldn't load checkout. Check your internet connection and try again.")
                .foregroundColor(Color(hex: 0x333333))
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                showError = false
                reloadToken = UUID()
            }
            .buttonStyle(LegacyProminentButtonStyle(tint: .accentColor))
            .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }

    private func onPaymentSucceeded() {
        let resolvedGameType = PendingPayment.gameType ?? gameType
        let resolvedSource = PendingPayment.source ?? premiumSource
        PendingPayment.gameType = nil
        PendingPayment.source = nil
        onSucceeded(GameSelection(gameType: resolvedGameType, premiumSource: resolvedSource))
    }
}
