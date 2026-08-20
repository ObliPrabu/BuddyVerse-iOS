import SwiftUI

/// Mirrors PremiumGameActivity/activity_premium_game.xml: a simple
/// placeholder shown for premium games that have been announced but aren't
/// built yet. No payment involved - there's nothing to unlock.
struct ComingSoonView: View {
    let gameName: String
    @EnvironmentObject private var router: Router

    private let bg = Color(hex: 0xE91E63)

    var body: some View {
        VStack(spacing: 0) {
            Text(gameName)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 40)

            Text("Native Premium Version\nCOMING SOON!")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)

            Button("Back to Menu") { router.pop() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(bg)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white)
                .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}
