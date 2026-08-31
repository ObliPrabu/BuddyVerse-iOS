import SwiftUI

/// Mirrors LobbyActivity/activity_lobby.xml: the premium expedition paywall -
/// pay 50 cents for just this one game, or subscribe ($4/month or $40/year)
/// for unlimited access to every premium game. Real internet multiplayer is
/// free and never routes through here anymore (see FriendTypeChoiceView).
///
/// Every button here requires a real signed-in account first (see
/// AuthManager/AccountView) - a purchase needs to be tied to something
/// recoverable on another device, not the per-device anonymous auth
/// multiplayer uses. A logged-out tap routes to AccountView instead of
/// straight to checkout; AccountView carries the same gameType/premiumSource
/// forward and jumps into PaymentWebView itself once sign-up/login succeeds.
struct LobbyView: View {
    let gameType: String
    @EnvironmentObject private var router: Router

    // Starts true so the paywall never flashes on screen for someone who
    // already paid - checked once per screen visit (SubscriptionManager
    // caches the result for the rest of the app session, so this is only a
    // real network round trip the first time in a given launch).
    @State private var isCheckingEntitlement = true
    // Guards against the user having already backed out of this screen
    // while the entitlement check was still in flight - without this,
    // router.replaceTop would land on whatever screen they backed into
    // instead of this one. Same pattern as AiGeneratingView's isCancelled.
    @State private var isCancelled = false

    // activity_lobby.xml has no @color/@drawable references - every color is
    // a literal hex with no values-night override, so this screen looks the
    // same in light and dark mode.
    private let baseBg = Color(hex: 0x1A237E)
    private let dimOverlay = Color.black.opacity(0x80 / 255.0)
    private let bodyCardBg = Color.black.opacity(0x44 / 255.0)
    private let joinButtonBg = Color(hex: 0xFF9800)

    var body: some View {
        ZStack {
            baseBg.ignoresSafeArea()
            dimOverlay.ignoresSafeArea()

            if isCheckingEntitlement {
                ProgressView()
                    .progressViewStyle(.circular)
                    .accentColor(.white)
                    .scaleEffect(1.6)
            } else {
                centerContent
            }

            VStack {
                HStack {
                    backButton
                    Spacer()
                }
                Spacer()
                HStack {
                    contactUsLink
                    Spacer()
                }
            }
            .padding(16)
        }
        .navigationBarHidden(true)
        .onAppear { checkEntitlement() }
        .onDisappear { isCancelled = true }
    }

    /// Skips straight past the paywall - same destination PaymentWebView's
    /// own success handler uses - if this account already has access,
    /// whether via an active subscription or having already paid the
    /// one-time unlock for this specific game.
    private func checkEntitlement() {
        guard AuthManager.isLoggedIn() else {
            isCheckingEntitlement = false
            return
        }
        SubscriptionManager.shared.isSubscribed { subscribed in
            guard !isCancelled else { return }
            if subscribed {
                router.replaceTop(with: .onePhoneSelection(gameType: gameType))
                return
            }
            SubscriptionManager.shared.isExpeditionUnlocked(gameType: gameType) { unlocked in
                guard !isCancelled else { return }
                if unlocked {
                    router.replaceTop(with: .onePhoneSelection(gameType: gameType))
                } else {
                    isCheckingEntitlement = false
                }
            }
        }
    }

    private var centerContent: some View {
        VStack(spacing: 0) {
            Text("Unlock Premium Access \u{1F48E}")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            Text("Play our Premium Access games, expertly crafted for the ultimate gaming experience\u{2014}only for 50 cents!")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(24)
                .background(bodyCardBg)
                .padding(.bottom, 30)

            Button {
                goToPayment("EXPEDITION")
            } label: {
                Text("PLAY PREMIUM EXPEDITIONS FOR ONLY 50\u{00A2}")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .background(joinButtonBg)
            }
            .buttonStyle(.plain)

            Text("\u{2014} or unlock every premium game \u{2014}")
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0xCC / 255.0))
                .padding(.top, 30)
                .padding(.bottom, 12)

            Button {
                goToPayment("SUB_MONTHLY")
            } label: {
                Text("$4 / month")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(baseBg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.white)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            Button {
                goToPayment("SUB_YEARLY")
            } label: {
                Text("$40 / year \u{2014} Recommended")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color(hex: 0x4CAF50))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private func goToPayment(_ source: String) {
        if AuthManager.isLoggedIn() {
            router.push(.paymentWebView(gameType: gameType, premiumSource: source))
        } else {
            router.push(.account(gameType: gameType, premiumSource: source))
        }
    }

    private var backButton: some View {
        Button("Back") { router.pop() }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(baseBg)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
            .buttonStyle(.plain)
    }

    private var contactUsLink: some View {
        Button("Contact Us") { router.push(.contactUs) }
            .font(.system(size: 14))
            .foregroundColor(.white)
            .opacity(0.8)
            .padding(10)
            .buttonStyle(.plain)
    }
}
