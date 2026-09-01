import SwiftUI

/// Shown in place of the usual "skip straight to the game" hop, whenever the
/// signed-in admin account (AuthManager.isAdmin()) taps a premium expedition
/// game it's already entitled to - see LobbyView.checkEntitlement(). Lets
/// that account either continue into the game it just tapped or jump into
/// AdminDashboardView instead, without a permanent top-right pill cluttering
/// the Welcome screen for everyone else, and without gating every ordinary
/// app launch behind an extra screen.
struct AdminHomeView: View {
    let gameType: String
    @EnvironmentObject private var router: Router

    private let baseBg = Color(hex: 0x1A237E)

    var body: some View {
        ZStack {
            baseBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Welcome back, Admin")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 40)

                Button {
                    router.replaceTop(with: .onePhoneSelection(gameType: gameType))
                } label: {
                    Text("🎮 Play Game")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(baseBg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)

                Button {
                    router.push(.adminDashboard)
                } label: {
                    Text("📊 Admin Dashboard")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color(hex: 0x4CAF50))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)

                // Signing out here (rather than just navigating away) means
                // the very next tap on this same premium game correctly
                // hits the normal paywall instead of this screen again -
                // AuthManager.isAdmin() only ever returns true for a real
                // signed-in session.
                Button {
                    AuthManager.logOut()
                    router.popToRoot()
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0xFF8A80))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 30)

            VStack {
                HStack {
                    backButton
                    Spacer()
                }
                Spacer()
            }
            .padding(16)
        }
        .navigationBarHidden(true)
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
}
