import ActivityKit
import Foundation

/// The Dynamic Island / Lock Screen Live Activity shown while a real
/// multiplayer game is in progress and the app gets backgrounded (swiped
/// away, not force-quit) - see LiveActivityManager (which starts/ends it)
/// and BuddyVerseWidget/BuddyVerseLiveActivity.swift (which renders it).
///
/// This one file is compiled into BOTH the main BuddyVerse app target (14.0
/// floor) and the BuddyVerseWidget extension target (16.2 floor, since
/// ActivityAttributes itself is a 16.2+ API) - see project.yml, where it's
/// listed explicitly under BuddyVerseWidget's sources alongside the
/// directory it actually lives in under BuddyVerse's own sources. Marked
/// `@available` so the main app target's older floor still compiles.
@available(iOS 16.2, *)
struct BuddyVerseActivityAttributes: ActivityAttributes {
    /// Changes over the life of the activity - in practice this app never
    /// updates it after starting (nobody's name changes mid-game), but
    /// ActivityAttributes requires a ContentState even for static content.
    struct ContentState: Codable, Hashable {
        var myName: String
        var opponentNames: String
    }

    /// Fixed for the life of the activity - the human-readable game name
    /// (e.g. "Tic-Tac-Toe"), shown above the "you vs them" row.
    var gameName: String
}
