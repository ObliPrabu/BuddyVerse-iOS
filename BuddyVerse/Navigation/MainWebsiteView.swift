import SwiftUI

/// Mirrors MainActivity: a WebView wrapper loading the real marketing site,
/// restricted to that trusted host - anything else opens in Safari instead.
struct MainWebsiteView: View {
    @EnvironmentObject private var router: Router
    private let trustedHost = "ambitious-desert-027b7dd0f.7.azurestaticapps.net"
    @State private var showError = false
    @State private var reloadToken = UUID()

    private var homeURL: URL { URL(string: "https://\(trustedHost)")! }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !showError {
                TrustedWebView(
                    url: homeURL,
                    allowedHosts: { $0 == trustedHost },
                    onLoadError: { showError = true }
                )
                .id(reloadToken)
            } else {
                VStack(spacing: 16) {
                    Text("Couldn't load the site. Check your connection and try again.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        showError = false
                        reloadToken = UUID()
                    }
                    .buttonStyle(LegacyProminentButtonStyle(tint: .accentColor))
                    .foregroundColor(.white)
                }
            }

            // This screen isn't hosted in a real NavigationStack (see
            // RootView's iOS-14-floor comment), so .navigationTitle's back
            // button never actually renders - every other screen provides
            // its own visible "Back" pill calling router.pop(), and this
            // one needs the same or there's no way off it but the app switcher.
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
        .navigationTitle("BuddyVerse.com")
        .navigationBarTitleDisplayMode(.inline)
    }
}
