import SwiftUI

/// Shown right after picking a mood, before Age Group, for the AI-generated
/// content flow (Jokes/Riddles/Trivia/Conversation) - picks how challenging
/// the generated content should be. Same welcome_gradient background and
/// Easy/Medium/Hard styling as BotDifficultyView, in that fixed order.
struct DifficultySelectionView: View {
    let gameType: String
    let mood: String
    @EnvironmentObject private var router: Router

    private var gameName: String {
        switch gameType {
        case "JOKES": return "Jokes"
        case "RIDDLES": return "Riddles"
        case "TRIVIA": return "Trivia"
        case "CONVERSATION": return "Conversation Starters"
        default: return "Activity"
        }
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
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("(\(gameName))")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: 0xE0F7FA))
                    .padding(.bottom, 40)

                ForEach(difficulties, id: \.value) { difficulty in
                    Button {
                        router.push(.ageGroup(gameType: gameType, mood: mood, difficulty: difficulty.value))
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
