import SwiftUI

/// Mirrors FriendTypeChoiceActivity/activity_friend_type_choice.xml: solid
/// blue background, "One Phone" (white/blue) and "Play Online" (orange,
/// free, only offered for GameCatalog.realMultiplayerGames) buttons, and a
/// Back button - matching Android's exact colors and copy.
struct FriendTypeChoiceView: View {
    let gameType: String
    @EnvironmentObject private var router: Router

    private let screenBg = Color(hex: 0x2196F3)

    var body: some View {
        ZStack {
            screenBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Play Together")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                Text("Choose how to play:")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(.bottom, GameCatalog.realMultiplayerGames.contains(gameType) ? 10 : 40)

                if GameCatalog.realMultiplayerGames.contains(gameType) {
                    Text("Play this with a friend (Recommended)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: 0xFFEB3B))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 30)
                }

                Button {
                    router.push(.instructionsChoice(GameSelection(gameType: gameType, isBot: false)))
                } label: {
                    Text("One Phone")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(screenBg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)

                if GameCatalog.realMultiplayerGames.contains(gameType) {
                    Button {
                        // Play Online is free - straight to the room screen,
                        // no payment. Games that support more than 2 players
                        // get an extra stop first to pick the room's player
                        // cap; Tic-Tac-Toe (2-player only) skips straight to
                        // the room screen.
                        if GameCatalog.multiSeatMultiplayerGames.contains(gameType) {
                            router.push(.maxPlayers(gameType: gameType))
                        } else {
                            router.push(.onlineLobby(gameType: gameType, maxPlayers: 2))
                        }
                    } label: {
                        Text("Play Online")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color(hex: 0xFF9800))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 30)
                }

                Button {
                    router.pop()
                } label: {
                    Text("Back")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0x333333))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0xAA / 255.0))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarHidden(true)
    }
}
