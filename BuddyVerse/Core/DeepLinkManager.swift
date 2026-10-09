import Foundation
import Combine

/// Bridges `buddyverse://` URLs (currently only the home-screen widget's
/// `.widgetURL`) into the app's navigation. `Router` is a `@StateObject`
/// scoped inside `RootView`, not reachable from `BuddyVerseApp`'s
/// `.onOpenURL`, so an opened URL is parsed into a route and stashed here;
/// `RootView` observes `pendingRoute` and pushes it onto its own `Router`,
/// then clears it.
final class DeepLinkManager: ObservableObject {
    // Only ever created/used on the main thread (SwiftUI view code), same as
    // every other cross-cutting singleton in this app - see ThemeManager and
    // MusicManager for the same pattern.
    nonisolated(unsafe) static let shared = DeepLinkManager()

    @Published var pendingRoute: AppRoute?

    private init() {}

    /// Handles `buddyverse://daily/jokes` and `buddyverse://daily/riddles` -
    /// the only links the widget currently sends. Anything else (unknown
    /// scheme/host/path) is ignored, same as a plain cold launch.
    func handle(_ url: URL) {
        guard url.scheme == "buddyverse", url.host == "daily" else { return }
        switch url.path {
        case "/jokes":
            pendingRoute = .game(GameSelection(gameType: "JOKES"))
        case "/riddles":
            pendingRoute = .game(GameSelection(gameType: "RIDDLES"))
        default:
            break
        }
    }
}
