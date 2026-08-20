import Foundation

// Mirrors GameCatalog.kt: the string constants used for GAME_TYPE on Android
// carry over unchanged here so the two codebases stay conceptually
// interchangeable (same wire values, same Firestore "gameType" field content
// for cross-referencing during multiplayer debugging).
enum GameCatalog {
    static let soloGamesWithNoBot: Set<String> = [
        "SUDOKU", "MAZE", "WORDSEARCH", "SLIDE", "HANGMAN", "SEQUENCE",
        "SPACE", "JUNGLE", "OCEAN", "SAVANNA", "STORM", "VOLCANO", "SWAMP", "MOUNTAIN"
    ]

    // Every game with real internet ("Two Phones") multiplayer wired up.
    static let realMultiplayerGames: Set<String> = [
        "TICTACTOE", "COUNT21", "MEMORY", "HANGMAN", "ARCTIC", "CAVE", "DESERT"
    ]

    // The subset of realMultiplayerGames that support more than 2 players in
    // one room (a live joining roster + host-triggered "Start Game", capped
    // at a host-chosen maxPlayers). Tic-Tac-Toe is deliberately left out of
    // this set - its board/symbols are fundamentally 2-player, so it keeps
    // the older "auto-start the instant one guest joins" flow instead.
    static let multiSeatMultiplayerGames: Set<String> = [
        "COUNT21", "MEMORY", "HANGMAN", "ARCTIC", "CAVE", "DESERT"
    ]

    // "Connect with friends" content - no bot opponent makes sense for these.
    static let socialItems: Set<String> = ["JOKES", "RIDDLES", "TRIVIA", "CONVERSATION"]
}
