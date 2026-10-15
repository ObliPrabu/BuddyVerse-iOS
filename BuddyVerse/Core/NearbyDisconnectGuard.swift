import SwiftUI

/// For the screens a real-multiplayer game passes through between the lobby
/// and the game itself (Hangman's mode choice, the instruction screens). They
/// have no message handling of their own, so before this, the only disconnect
/// handler still installed belonged to the lobby - which only changes a text
/// label on a screen nobody is looking at. A guest waiting on "Waiting for
/// your friend to choose..." was never told the host had left.
///
/// This swaps in a handler that sends the player to the same "your friend
/// left" screen the games use. It only swaps the disconnect handler (never the
/// message buffer), so the game screen's own setListeners still replays
/// everything that arrived early and then takes over.
private struct NearbyDisconnectGuard: ViewModifier {
    let isNearby: Bool
    @EnvironmentObject private var router: Router
    @State private var handled = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard isNearby else { return }
            InternetConnectionManager.shared.setInterstitialDisconnectListener {
                DispatchQueue.main.async {
                    guard !handled else { return }
                    handled = true
                    InternetConnectionManager.shared.stop()
                    router.push(.opponentDisconnected)
                }
            }
        }
    }
}

extension View {
    func guardNearbyDisconnect(_ isNearby: Bool) -> some View {
        modifier(NearbyDisconnectGuard(isNearby: isNearby))
    }
}
