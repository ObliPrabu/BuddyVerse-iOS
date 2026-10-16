import SwiftUI

/// Where the home-screen widget lands (`buddyverse://daily/question`): the
/// day's joke/riddle/trivia question under a "Question of the Day" heading,
/// with a button into the matching game. Mirrors Android's
/// DailyQuestionActivity; both read today's pick from DailyContentPool.
struct DailyQuestionView: View {
    @EnvironmentObject private var router: Router
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var systemScheme
    @State private var showAnswer = false

    private let pick = DailyContentPool.pick(for: Date())

    private var isDark: Bool { theme.isDarkActive(systemScheme: systemScheme) }
    private var screenBackground: Color { isDark ? Color(hex: 0x121212) : .white }
    private var textPrimary: Color { isDark ? Color(hex: 0xF5F5F5) : Color(hex: 0x333333) }
    private var textSecondary: Color { isDark ? Color(hex: 0xCCCCCC) : Color(hex: 0x666666) }
    private var accentColor: Color { isDark ? Color(hex: 0x8C9EFF) : Color(hex: 0x1A237E) }

    private var gameName: String {
        switch pick.kind {
        case .joke: return "Jokes"
        case .riddle: return "Riddles"
        case .trivia: return "Trivia"
        }
    }

    private var gameType: String {
        switch pick.kind {
        case .joke: return "JOKES"
        case .riddle: return "RIDDLES"
        case .trivia: return "TRIVIA"
        }
    }

    private var answerLabel: String { pick.kind == .joke ? "Show punchline" : "Show answer" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            screenBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("Question of the Day")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(accentColor)
                        .multilineTextAlignment(.center)

                    Text(pick.primary)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if showAnswer {
                        Text(pick.secondary)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button { showAnswer = true } label: {
                            Text(answerLabel)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        router.replaceTop(with: .game(GameSelection(gameType: gameType)))
                    } label: {
                        Text("Go to \(gameName)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: 0x6A5AE0))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                .padding(24)
                .padding(.top, 56)
                .frame(maxWidth: .infinity)
            }

            Button {
                router.pop()
            } label: {
                Text("Back")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0x757575))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}
