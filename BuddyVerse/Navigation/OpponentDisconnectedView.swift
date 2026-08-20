import SwiftUI

/// Mirrors OpponentDisconnectedActivity/activity_opponent_disconnected.xml:
/// same welcome_gradient background, the 😕 emoji, and the exact bold-white
/// title + teal subtitle copy, with a white/dark "Back" button.
struct OpponentDisconnectedView: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("😕")
                    .font(.system(size: 60))
                    .padding(.bottom, 20)

                Text("Opponent Disconnected")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)

                Text("The other phone lost connection or left the game.")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: 0xE0F7FA))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)

                Button {
                    router.popToRoot()
                } label: {
                    Text("Back")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: 0x333333))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(30)
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}
