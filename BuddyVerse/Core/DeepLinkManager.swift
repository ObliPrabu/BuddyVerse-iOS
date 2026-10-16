import Foundation
import Combine

/// Bridges `buddyverse://` URLs (currently only the home-screen widget's
/// `.widgetURL`) into the app's navigation. `Router` is a `@StateObject`
/// scoped inside `RootView`, not reachable from `BuddyVerseApp`'s
/// `.onOpenURL`, so an opened URL is parsed into a route and stashed here;
/// `RootView` observes `pendingRoute` and pushes it onto its own `Router`,
/// then clears it.
@MainActor
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    @Published var pendingRoute: AppRoute?

    private init() {}

    /// Handles `buddyverse://daily/question` (what the widget sends - opens
    /// the Question of the Day screen) plus the older `/jokes` and `/riddles`
    /// direct-to-game links. Anything else (unknown
    /// scheme/host/path) is ignored, same as a plain cold launch.
    func handle(_ url: URL) {
        guard url.scheme == "buddyverse", url.host == "daily" else { return }
        switch url.path {
        case "/question":
            pendingRoute = .dailyQuestion
        case "/jokes":
            pendingRoute = .game(GameSelection(gameType: "JOKES"))
        case "/riddles":
            pendingRoute = .game(GameSelection(gameType: "RIDDLES"))
        default:
            break
        }
    }
}
