import SwiftUI

/// First-launch Terms and Conditions gate: shows TermsText and requires all
/// three checkmarks before "I Agree" works. Mirrors Android's TermsActivity.
/// Rendered by RootView as a full-screen overlay (like EnterNameView) until
/// `accepted_terms` is saved; no Back/Skip.
struct TermsView: View {
    var onAccept: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var systemScheme
    @State private var agreeTerms = false
    @State private var readPrivacy = false
    @State private var ageOk = false

    private var isDark: Bool { theme.isDarkActive(systemScheme: systemScheme) }
    private var screenBackground: Color { isDark ? Color(hex: 0x121212) : .white }
    private var textPrimary: Color { isDark ? Color(hex: 0xF5F5F5) : Color(hex: 0x333333) }
    private var textSecondary: Color { isDark ? Color(hex: 0xCCCCCC) : Color(hex: 0x666666) }
    private var textMuted: Color { Color(hex: 0x999999) }
    private var allChecked: Bool { agreeTerms && readPrivacy && ageOk }

    var body: some View {
        ZStack {
            screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Terms and Conditions")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(textPrimary)
                    .padding(.bottom, 4)
                Text(TermsText.lastUpdated)
                    .font(.system(size: 13))
                    .foregroundColor(textMuted)
                    .padding(.bottom, 12)

                ScrollView {
                    Text(TermsText.body)
                        .font(.system(size: 15))
                        .foregroundColor(textSecondary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 10) {
                    checkRow("I have read and agree to the Terms and Conditions", isOn: $agreeTerms)
                    checkRow("I have read the Privacy Policy", isOn: $readPrivacy)
                    if let url = URL(string: TermsText.privacyURL) {
                        Link("Open the Privacy Policy", destination: url)
                            .font(.system(size: 14))
                            .padding(.leading, 34)
                    }
                    checkRow("I am 13 or older, or I have a parent or guardian's permission", isOn: $ageOk)
                }
                .padding(.vertical, 12)

                Button {
                    guard allChecked else { return }
                    UserDefaults.standard.set(true, forKey: "accepted_terms")
                    onAccept()
                } label: {
                    Text("I Agree")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(hex: 0x2196F3).opacity(allChecked ? 1 : 0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!allChecked)
            }
            .padding(20)
        }
    }

    private func checkRow(_ text: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24))
                    .foregroundColor(isOn.wrappedValue ? Color(hex: 0x2196F3) : textMuted)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundColor(textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}
