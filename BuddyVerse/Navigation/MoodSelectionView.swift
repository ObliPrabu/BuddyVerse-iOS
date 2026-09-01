import SwiftUI

/// Mirrors MoodSelectionActivity/activity_mood_selection.xml: the same
/// welcome_gradient background, exact per-mood button colors/copy (with
/// emoji), and a Back button - picks the tone AI content should be written
/// in, then continues to AgeGroupView.
struct MoodSelectionView: View {
    let gameType: String
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

    private let moods: [(label: String, value: String, color: Color)] = [
        ("Feeling Great! 😄", "HAPPY", Color(hex: 0x4CAF50)),
        ("A bit down... 😔", "SAD", Color(hex: 0x2196F3)),
        ("Just Bored 🥱", "BORED", Color(hex: 0xFF9800)),
        ("Super Excited! 🤩", "EXCITED", Color(hex: 0xE91E63))
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("How's your mood today?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("(\(gameName))")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: 0xE0F7FA))
                    .padding(.bottom, 40)

                ForEach(moods, id: \.value) { mood in
                    Button {
                        // Jokes never calls AI (see AiContentService.generate)
                        // and always uses the static joke pool, so a
                        // difficulty pick would have nothing to affect -
                        // skip straight to Age Group with a placeholder value.
                        if gameType == "JOKES" {
                            router.push(.ageGroup(gameType: gameType, mood: mood.value, difficulty: "MEDIUM"))
                        } else {
                            router.push(.difficultySelection(gameType: gameType, mood: mood.value))
                        }
                    } label: {
                        Text(mood.label)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(mood.color)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, mood.value == "EXCITED" ? 30 : 10)
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
