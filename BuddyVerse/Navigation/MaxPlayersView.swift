import SwiftUI

/// Shown once, right after paying to unlock online play, only for games that
/// support more than 2 people in one room (GameCatalog.multiSeatMultiplayerGames).
/// The host picks how many players the room should allow (2-8) before
/// getting to the actual "Create/Join Game" screen - this becomes the room's
/// maxPlayers, enforced by InternetConnectionManager so nobody can join past
/// that cap. Mirrors MaxPlayersActivity/activity_max_players.xml.
struct MaxPlayersView: View {
    let gameType: String
    @EnvironmentObject private var router: Router

    @State private var maxPlayers = 4

    private let baseBg = Color(hex: 0x1A237E)

    var body: some View {
        ZStack {
            baseBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("How many players?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 12)

                Text("Pick the most people who can join this room. You can start once at least 2 have joined.")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)

                Stepper(value: $maxPlayers, in: 2...8) {
                    Text("\(maxPlayers) players")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)

                Button("Continue") {
                    router.push(.onlineLobby(gameType: gameType, maxPlayers: maxPlayers))
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color(hex: 0xFF9800))
                .buttonStyle(.plain)
            }
            .padding(20)

            VStack {
                HStack {
                    Button("Back") { router.pop() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(baseBg)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .buttonStyle(.plain)
                    Spacer()
                }
                Spacer()
            }
            .padding(16)
        }
        .navigationBarHidden(true)
    }
}
