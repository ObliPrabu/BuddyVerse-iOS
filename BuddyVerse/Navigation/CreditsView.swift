import SwiftUI

/// Mirrors CreditsActivity/activity_credits.xml: the exact "Meet the Makers"
/// copy, screen_background/text color swap from colors.xml, a top-left gray
/// "Back" pill, and confetti that celebrates whenever this screen is opened.
struct CreditsView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var systemScheme

    private var isDark: Bool { theme.isDarkActive(systemScheme: systemScheme) }

    private var screenBackground: Color { isDark ? Color(hex: 0x121212) : .white }
    private var textPrimary: Color { isDark ? Color(hex: 0xF5F5F5) : Color(hex: 0x333333) }
    private var textSecondary: Color { isDark ? Color(hex: 0xCCCCCC) : Color(hex: 0x666666) }
    private var textMuted: Color { Color(hex: 0x999999) }
    private var accentColor: Color { isDark ? Color(hex: 0x8C9EFF) : Color(hex: 0x1A237E) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            screenBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Text("🎉")
                        .font(.system(size: 40))
                        .padding(.bottom, 8)

                    Text("Meet the Makers")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(textPrimary)
                        .padding(.bottom, 8)

                    Text("The kid who dreamed up, designed, and built BuddyVerse.")
                        .font(.system(size: 16))
                        .foregroundColor(textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 30)

                    Text("Mithran ObliPrabu")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(accentColor)
                        .padding(.bottom, 30)

                    Text("🏫 Milltown · Bridgewater, New Jersey")
                        .font(.system(size: 16))
                        .foregroundColor(textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 30)

                    Text("BuddyVerse — a school project, made to help people make friends. 💛")
                        .font(.system(size: 14))
                        .foregroundColor(textMuted)
                        .multilineTextAlignment(.center)
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
        .navigationBarHidden(true)
        .confettiOverlay(confetti)
        .onAppear { confetti.start() }
    }
}
