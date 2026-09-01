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
            }
            .padding(.horizontal, 30)
        }
        .navigationBarHidden(true)
    }
}
