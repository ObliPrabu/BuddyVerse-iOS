import Foundation
import FirebaseFirestore

/// Play-count tracking, free-text feedback, and content/bug reports - all
/// self-reported, all written straight to Firestore with no auth requirement
/// (most single-player game launches never establish any auth session at
/// all), and all readable only by the one admin account via the in-app
/// Admin Dashboard.
enum AppFeedbackService {
    private static var db: Firestore { Firestore.firestore() }

    /// Called exactly once per game launch, from the single choke point
    /// every game route funnels through (RootView's `.game` case) - never
    /// call this from an individual game screen directly, or a re-render
    /// could double-count.
    static func incrementPlayCount(gameType: String) {
        db.collection("playCounts").document(gameType)
            .setData(["count": FieldValue.increment(Int64(1))], merge: true)
    }

    static func submitFeedback(gameType: String, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        db.collection("feedback").addDocument(data: [
            "gameType": gameType,
            "message": trimmed,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    static func submitReport(gameType: String, reason: String, detail: String) {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        db.collection("reports").addDocument(data: [
            "gameType": gameType,
            "reason": reason,
            "detail": trimmedDetail,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    /// Human-readable name for a GAME_TYPE constant, used by the Feedback/
    /// Report sheets and the Admin Dashboard's play-count list - mirrors the
    /// display names already used across Welcome/game screens.
    static func displayName(for gameType: String) -> String {
        switch gameType {
        case "JOKES": return "Jokes"
        case "RIDDLES": return "Riddles"
        case "TRIVIA": return "Trivia"
        case "CONVERSATION": return "Conversation Starters"
        case "TICTACTOE": return "Tic-Tac-Toe"
        case "RPS": return "Rock Paper Scissors"
        case "SUDOKU": return "Sudoku"
        case "MAZE": return "Amazing Maze"
        case "COUNT21": return "Count to 21"
        case "WORDSEARCH": return "Word Search"
        case "MEMORY": return "Memory Match"
        case "SEQUENCE": return "Memory Sequence"
        case "SLIDE": return "Slide Puzzle"
        case "HANGMAN": return "Hangman"
        case "MATH": return "Math Sprint"
        case "SPACE": return "Space Explorer"
        case "JUNGLE": return "Jungle Run"
        case "OCEAN": return "Ocean Dive"
        case "MOUNTAIN": return "Mountain Climb"
        case "DESERT": return "Desert Trek"
        case "VOLCANO": return "Volcano Climb"
        case "ARCTIC": return "Arctic Trek"
        case "SAVANNA": return "Savanna Safari"
        case "CAVE": return "Cave Explorer"
        case "SWAMP": return "Swamp Trek"
        case "STORM": return "Storm Chase"
        default: return gameType
        }
    }

    static let reportReasons = [
        "Bug or glitch",
        "Game froze or crashed",
        "Confusing instructions",
        "Inappropriate content",
        "Other"
    ]
}
