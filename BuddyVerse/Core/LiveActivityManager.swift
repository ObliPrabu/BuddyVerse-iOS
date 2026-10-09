import ActivityKit
import Foundation

/// Starts/ends the "you vs them" Dynamic Island / Lock Screen Live Activity
/// for a real multiplayer game whenever the app is backgrounded (swiped
/// away, not force-quit) mid-game - see BuddyVerseApp's scenePhase observer
/// for when start()/end() actually get called, and RootView's `.game` case
/// for where currentContext gets set/cleared as the player enters/leaves a
/// game screen. iOS 16.2+ only (Live Activities don't exist before that);
/// every call here silently no-ops on older iOS, so the app's 14.0 floor is
/// completely untouched - this is the only file in the main app target that
/// references ActivityKit at all, and only inside `if #available` blocks.
enum LiveActivityManager {
    /// Set by RootView whenever the top of the router stack is a real
    /// multiplayer game (GameSelection.isNearby with 2+ players) - not tied
    /// to SwiftUI view lifecycle beyond that, since the whole point of a
    /// Live Activity is surviving into the background after the view
    /// itself is no longer visible. `nonisolated(unsafe)` matches
    /// InternetConnectionManager's own `shared` - only ever touched from
    /// the main thread in practice (SwiftUI view lifecycle callbacks and
    /// BuddyVerseApp's scenePhase observer, both main-actor-bound), so
    /// Swift's strict concurrency checking just needs the escape hatch, not
    /// a real actor.
    nonisolated(unsafe) static var currentContext: (gameType: String, myName: String, opponentNames: String)?

    static func start() {
        guard #available(iOS 16.2, *), let context = currentContext else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Never leave a stale activity running under an old game's names if
        // the player backgrounds mid-game more than once in a session.
        end()
        let attributes = BuddyVerseActivityAttributes(gameName: AppFeedbackService.displayName(for: context.gameType))
        let state = BuddyVerseActivityAttributes.ContentState(myName: context.myName, opponentNames: context.opponentNames)
        do {
            _ = try Activity<BuddyVerseActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            // Non-critical convenience feature - never worth surfacing an
            // error for (e.g. the player has Live Activities disabled in
            // Settings, which areActivitiesEnabled already mostly guards,
            // or a transient system-level request failure).
        }
    }

    static func end() {
        guard #available(iOS 16.2, *) else { return }
        Task {
            for activity in Activity<BuddyVerseActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
