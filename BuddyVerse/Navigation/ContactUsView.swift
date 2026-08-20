import SwiftUI

/// Mirrors ContactUsActivity/activity_contact_us.xml: the light/dark
/// screen_background + screen_text_primary swap from colors.xml, the exact
/// phone number / Discord link copy and colors, and a top-left gray "Back"
/// pill instead of a bottom text link.
struct ContactUsView: View {
    @EnvironmentObject private var router: Router
    @Environment(\.openURL) private var openURL
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var systemScheme

    private var isDark: Bool { theme.isDarkActive(systemScheme: systemScheme) }

    private var screenBackground: Color { isDark ? Color(hex: 0x121212) : .white }
    private var textPrimary: Color { isDark ? Color(hex: 0xF5F5F5) : Color(hex: 0x333333) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Contact Us")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(textPrimary)
                    .padding(.bottom, 40)

                Button {
                    if let url = URL(string: "tel:+17322581971") { openURL(url) }
                } label: {
                    Text("+1 (732) 258-1971")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: 0x2196F3))
                        .padding(10)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)

                Button {
                    if let url = URL(string: "https://discord.gg/W3GQ3fX4J") { openURL(url) }
                } label: {
                    Text("Join our Discord")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: 0x5865F2))
                        .padding(10)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
    }
}
