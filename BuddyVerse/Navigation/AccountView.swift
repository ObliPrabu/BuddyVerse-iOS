import SwiftUI

/// Mirrors AccountActivity/activity_account.xml: sign up / log in screen
/// shown in front of any premium payment (one-time expedition unlock or
/// either subscription tier) - LobbyView routes here first whenever
/// AuthManager.isLoggedIn() is false, since a purchase needs a real
/// recoverable account for SubscriptionManager to key off, not the
/// per-device anonymous auth multiplayer uses. gameType/premiumSource are
/// just passed straight through from LobbyView so, once signed in, this can
/// jump directly into PaymentWebView for the purchase the player originally
/// tapped - no need to bounce back through LobbyView.
struct AccountView: View {
    let gameType: String
    let premiumSource: String

    @EnvironmentObject private var router: Router

    @State private var isSignUpMode = true
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
            Text(isSignUpMode ? "Create an account to continue" : "Log in to continue")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text("An account keeps your premium access with you, even on a new device.")
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0xCC / 255.0))
                .multilineTextAlignment(.center)
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
                    .textContentType(isSignUpMode ? .newPassword : .password)
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
                Text(isSubmitting ? "..." : (isSignUpMode ? "Sign Up" : "Log In"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(hex: 0x4CAF50))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .padding(.bottom, 12)

            Button {
                isSignUpMode.toggle()
                errorMessage = ""
            } label: {
                Text(isSignUpMode ? "Already have an account? Log In" : "Need an account? Sign Up")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
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
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }
        isSubmitting = true
        errorMessage = ""

        func handleResult(_ success: Bool, _ error: String?) {
            isSubmitting = false
            if success {
                router.replaceTop(with: .paymentWebView(gameType: gameType, premiumSource: premiumSource))
            } else {
                errorMessage = error ?? "Something went wrong. Try again."
            }
        }

        if isSignUpMode {
            AuthManager.signUp(email: trimmedEmail, password: password, onResult: handleResult)
        } else {
            AuthManager.logIn(email: trimmedEmail, password: password, onResult: handleResult)
        }
    }
}
