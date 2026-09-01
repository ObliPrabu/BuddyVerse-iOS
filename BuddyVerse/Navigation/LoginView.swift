import SwiftUI

/// A plain "log into an existing account" screen, reachable straight from
/// WelcomeView - unlike AccountView (which only ever appears mid-purchase and
/// jumps into PaymentWebView on success), this has nothing to hand off to
/// afterward, so success just pops back to whatever screen pushed it.
/// Signing in here is what makes WelcomeView's admin dashboard entry point
/// appear for the one designated admin account (see AuthManager.isAdmin()) -
/// there's no separate "admin login," it's the same account system every
/// premium purchase already uses.
struct LoginView: View {
    @EnvironmentObject private var router: Router

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isSubmitting = false

    private let baseBg = Color(hex: 0x1A237E)

    var body: some View {
        ZStack {
            baseBg.ignoresSafeArea()

            centerContent

            VStack {
                HStack {
                    backButton
                    Spacer()
                }
                Spacer()
            }
            .padding(16)
        }
        .navigationBarHidden(true)
    }

    private var centerContent: some View {
        VStack(spacing: 0) {
            Text("Log In")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 30)

            placeholderField(placeholder: "Email", text: $email) {
                TextField("", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .padding(.bottom, 16)

            placeholderField(placeholder: "Password", text: $password) {
                SecureField("", text: $password)
                    .textContentType(.password)
            }
            .padding(.bottom, 8)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xFF8A80))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }

            Button {
                submit()
            } label: {
                Text(isSubmitting ? "..." : "Log In")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(hex: 0x4CAF50))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    /// `TextField`/`SecureField`'s `prompt:` initializer needs iOS 15 - this
    /// is the pre-15 way to get the same white-on-dark placeholder text:
    /// layer it under the field by hand and only show it while empty.
    private func placeholderField<Content: View>(
        placeholder: String,
        text: Binding<String>,
        @ViewBuilder field: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundColor(Color.white.opacity(0xAA / 255.0))
            }
            field()
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.4)), alignment: .bottom)
    }

    private var backButton: some View {
        Button("Back") { router.pop() }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(baseBg)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
            .buttonStyle(.plain)
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Enter an email and password."
            return
        }
        isSubmitting = true
        errorMessage = ""

        AuthManager.logIn(email: trimmedEmail, password: password) { success, error in
            isSubmitting = false
            if success {
                // Without this, a premium-access check made earlier in this
                // app session (even just opening the app while logged out)
                // stays cached as "not entitled" for the rest of the
                // session - logging in would silently never un-stick it.
                SubscriptionManager.shared.clearCache()
                router.pop()
            } else {
                errorMessage = error ?? "Something went wrong. Try again."
            }
        }
    }
}
