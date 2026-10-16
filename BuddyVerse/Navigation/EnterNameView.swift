import SwiftUI

/// A mandatory, first-launch-only gate shown once per device before the rest
/// of the app is usable - asks for a first name only (never an email or full
/// name, matching AppFeedbackService.submitAppUser's COPPA-safe reasoning,
/// since this app's Kid content mode means it can genuinely be used by
/// children). Deliberately has no Back/Skip button - see class doc comment
/// on Android's EnterNameActivity for the parallel reasoning there.
///
/// Rendered by RootView as a full-screen overlay sitting on top of
/// WelcomeView (already mounted underneath, not a separate pushed route), so
/// once this and GetUpdatesView right after it are both dismissed, the
/// already-ready Welcome screen is simply revealed - no relaunch, no
/// blank-state risk. There's also no swipe-back gesture anywhere in this app
/// (see RootView's own doc comment), so unlike Android there's no back
/// gesture to separately block.
struct EnterNameView: View {
    var onContinue: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var systemScheme
    @State private var firstName = ""
    @State private var showEmptyNameAlert = false
    @State private var alertText = "Please enter your name to continue."

    private var isDark: Bool { theme.isDarkActive(systemScheme: systemScheme) }
    private var screenBackground: Color { isDark ? Color(hex: 0x121212) : .white }
    private var textPrimary: Color { isDark ? Color(hex: 0xF5F5F5) : Color(hex: 0x333333) }
    private var textSecondary: Color { isDark ? Color(hex: 0xCCCCCC) : Color(hex: 0x666666) }
    private var textMuted: Color { isDark ? Color(hex: 0x999999) : Color(hex: 0x999999) }

    var body: some View {
        ZStack {
            screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("👋 Welcome to BuddyVerse!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)

                Text("What should we call you? Just a first name — no email, no password.")
                    .font(.system(size: 15))
                    .foregroundColor(textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 30)

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
                        alertText = "Please enter your name to continue."
                        showEmptyNameAlert = true
                        return
                    }
                    // Only a first name is wanted - never an email or a full
                    // name (the copy above promises that).
                    guard !trimmed.contains("@"), trimmed.count <= 30 else {
                        alertText = "Just a first name, please - no email or full name."
                        showEmptyNameAlert = true
                        return
                    }
                    AppFeedbackService.submitAppUser(firstName: trimmed)
                    UserDefaults.standard.set(true, forKey: "has_entered_name")
                    UserDefaults.standard.set(trimmed, forKey: "user_first_name")
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(hex: 0x2196F3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(30)
        }
        .alert(isPresented: $showEmptyNameAlert) {
            Alert(title: Text(alertText))
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
