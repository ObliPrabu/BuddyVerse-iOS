import SwiftUI

/// Mirrors BotDifficultyActivity/activity_bot_difficulty.xml: the same
/// welcome_gradient purple->indigo->teal diagonal background (no dark-mode
/// override on Android, so this doesn't branch on theme), with the three
/// difficulty buttons in their exact Android colors. IS_BOT is always set
/// true here even for solo-only games (Sudoku, Maze, etc.) that never read
/// it - matches the Android behavior exactly, where it's simply inert for
/// those games.
struct BotDifficultyView: View {
    let gameType: String
    @EnvironmentObject private var router: Router

    private var subtitle: String {
        GameCatalog.soloGamesWithNoBot.contains(gameType)
            ? "Choose how hard the game is:"
            : "Choose how smart the bot is:"
    }

    private let difficulties: [(label: String, value: String, color: Color)] = [
        ("Easy", "EASY", Color(hex: 0x4CAF50)),
        ("Medium", "MEDIUM", Color(hex: 0xFF9800)),
        ("Hard", "HARD", Color(hex: 0xF44336))
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Select Difficulty")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                Text(subtitle)
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .padding(.bottom, 40)

                ForEach(difficulties, id: \.value) { difficulty in
                    Button {
                        let selection = GameSelection(gameType: gameType, difficulty: difficulty.value, isBot: true)
                        router.push(.instructionsChoice(selection))
                    } label: {
                        Text(difficulty.label)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(difficulty.color)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, difficulty.value == "HARD" ? 30 : 10)
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
