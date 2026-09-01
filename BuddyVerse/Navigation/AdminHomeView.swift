import SwiftUI

/// Shown automatically, once, right when the app launches while signed in
/// as the one designated admin account (AuthManager.isAdmin()) - see
/// WelcomeView's onAppear. Lets that account either drop straight into the
/// normal app (same as any other player) or jump into AdminDashboardView,
/// without a permanent top-right pill cluttering the Welcome screen for
/// everyone else.
struct AdminHomeView: View {
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
                    router.pop()
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
