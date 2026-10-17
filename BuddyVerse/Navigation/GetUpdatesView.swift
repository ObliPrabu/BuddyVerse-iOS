import SwiftUI

/// Mirrors GetUpdatesActivity/activity_get_updates.xml: a deliberately
/// minimal opt-in for update notifications - first name only, no email, no
/// password. See AppFeedbackService.submitUpdateOptIn/checkForUpdate for the
/// full reasoning. The local `wants_notifications` flag this screen sets is
/// what WelcomeView checks on appear to decide whether to bother calling
/// checkForUpdate() at all.
///
/// Reached two ways, exactly like Android's single Activity serves both: the
/// optional "🔔 Get Updates" link on the Welcome screen's footer (`onBack`
/// pops the normal router route), and as the second, still-mandatory step of
/// the first-launch gate right after EnterNameView (`onBack` there just
/// finishes the gate, revealing the already-mounted Welcome screen
/// underneath) - either way "Back" just closes this screen.
struct GetUpdatesView: View {
    var onBack: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var systemScheme
    // The gate already asked for the name - reuse it instead of asking again.
    @State private var firstName = UserDefaults.standard.string(forKey: "user_first_name") ?? ""
    @State private var isSubscribed = UserDefaults.standard.bool(forKey: "wants_notifications")
    @State private var showEmptyNameAlert = false
    @State private var alertText = "Please enter your name to subscribe."

    private var isDark: Bool { theme.isDarkActive(systemScheme: systemScheme) }
    private var screenBackground: Color { isDark ? Color(hex: 0x121212) : .white }
    private var textPrimary: Color { isDark ? Color(hex: 0xF5F5F5) : Color(hex: 0x333333) }
    private var textSecondary: Color { isDark ? Color(hex: 0xCCCCCC) : Color(hex: 0x666666) }
    private var textMuted: Color { isDark ? Color(hex: 0x999999) : Color(hex: 0x999999) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("🔔 Stay in the Loop")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)

                Text("Want a heads-up when new games or features come out? Just your first name — no email needed.")
                    .font(.system(size: 15))
                    .foregroundColor(textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 30)

                if isSubscribed {
                    subscribedGroup
                } else {
                    formGroup
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                onBack()
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
        .alert(isPresented: $showEmptyNameAlert) {
            Alert(title: Text(alertText))
        }
    }

    private var formGroup: some View {
        VStack(spacing: 0) {
            placeholderField(placeholder: "Your first name", text: $firstName) {
                TextField("", text: $firstName)
                    .foregroundColor(textPrimary)
                    .textContentType(.givenName)
                    .autocapitalization(.words)
                    .disableAutocorrection(true)
            }
            .padding(.bottom, 20)

            Button {
                let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    alertText = "Please enter your name to subscribe."
                    showEmptyNameAlert = true
                    return
                }
                guard !trimmed.contains("@"), trimmed.count <= 20, !trimmed.contains(where: { $0.isNumber || $0.isWhitespace }) else {
                    alertText = "Just a first name, please - one word, no email, numbers or last name."
                    showEmptyNameAlert = true
                    return
                }
                AppFeedbackService.submitUpdateOptIn(firstName: trimmed)
                UserDefaults.standard.set(true, forKey: "wants_notifications")
                isSubscribed = true
            } label: {
                Text("🔔 Notify Me About Updates")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(hex: 0x2196F3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var subscribedGroup: some View {
        VStack(spacing: 16) {
            Text("✓ You're Subscribed")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: 0x4CAF50))

            Button {
                UserDefaults.standard.set(false, forKey: "wants_notifications")
                isSubscribed = false
            } label: {
                Text("Turn off updates")
                    .font(.system(size: 14))
                    .foregroundColor(textMuted)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
    }

    /// `TextField`'s `prompt:` initializer needs iOS 15 - this is the
    /// pre-15 way to get the same placeholder text: layer it under the
    /// field by hand and only show it while empty.
    private func placeholderField<Content: View>(
        placeholder: String,
        text: Binding<String>,
        @ViewBuilder field: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundColor(textMuted)
            }
            field()
        }
        .padding(.vertical, 8)
        .overlay(Rectangle().frame(height: 1).foregroundColor(textMuted), alignment: .bottom)
    }
}
