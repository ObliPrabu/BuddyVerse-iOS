import SwiftUI

/// Mirrors AgeGroupActivity/activity_age_group.xml: same welcome_gradient
/// background, exact Kid/Adult button colors + emoji copy, and a Back
/// button - shown right after picking a difficulty, asks whether content
/// should be written for a kid or an adult.
struct AgeGroupView: View {
    let gameType: String
    let mood: String
    let difficulty: String
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

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Who's playing?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("(\(gameName))")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: 0xE0F7FA))
                    .padding(.bottom, 40)

                Button {
                    router.push(.aiGenerating(gameType: gameType, mood: mood, ageGroup: "KID", difficulty: difficulty))
                } label: {
                    Text("Kid 🧒")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color(hex: 0x4CAF50))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)

                Button {
                    router.push(.aiGenerating(gameType: gameType, mood: mood, ageGroup: "ADULT", difficulty: difficulty))
                } label: {
                    Text("Adult 🧑")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color(hex: 0x2196F3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 30)

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
