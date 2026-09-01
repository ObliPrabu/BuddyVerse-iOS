import Foundation
import SwiftUI

// Mirrors the "bag of Intent extras" every Android screen threads forward
// (GAME_TYPE/DIFFICULTY/IS_BOT/IS_NEARBY/MOOD/AGE_GROUP/AI_ITEMS/WORD_MODE).
// Passed by value along the NavigationStack path instead of Intent extras -
// same idea (immutable state handed to the next screen), different plumbing.
struct GameSelection: Hashable {
    var gameType: String
    var difficulty: String? = nil
    var isBot: Bool = false
    var isNearby: Bool = false
    var mood: String? = nil
    var ageGroup: String? = nil
    var aiItems: [String]? = nil
    var wordMode: String? = nil
    var premiumSource: String = "EXPEDITION"
    var players: [Player]? = nil
}

// Every screen BuddyVerse can navigate to. NavigationStack's path is just
// `[AppRoute]`, so pushing a screen is the direct equivalent of
// `startActivity(Intent(...))`, and `path.removeLast()` (or popping via the
// back button) is `finish()`.
enum AppRoute: Hashable {
    case mainWebsite
    case ageGroup(gameType: String, mood: String, difficulty: String)
    case moodSelection(gameType: String)
    case difficultySelection(gameType: String, mood: String)
    case aiGenerating(gameType: String, mood: String, ageGroup: String, difficulty: String)
    case onePhoneSelection(gameType: String)
    case friendTypeChoice(gameType: String)
    case botDifficulty(gameType: String)
    case lobby(gameType: String)
    case comingSoon(gameName: String)
    case account(gameType: String, premiumSource: String)
    case paymentWebView(gameType: String, premiumSource: String)
    case maxPlayers(gameType: String)
    case onlineLobby(gameType: String, maxPlayers: Int)
    case hangmanModeChoice(GameSelection)
    case instructionsChoice(GameSelection)
    case instructionsView(GameSelection)
    case game(GameSelection)
    case mathSprintSelection
    case contactUs
    case credits
    case opponentDisconnected
    case login
}

// The single place that maps a GAME_TYPE string to its destination screen -
// mirrors InstructionsChoiceActivity.Companion.createGameIntent(), the one
// hub every flow funnels through before a game actually opens. Adding a new
// game means adding one case here and nowhere else.
enum GameRouter {
    @ViewBuilder
    static func gameView(for selection: GameSelection) -> some View {
        switch selection.gameType {
        case "JOKES": JokesView(selection: selection)
        case "RIDDLES": RiddlesView(selection: selection)
        case "TRIVIA": TriviaView(selection: selection)
        case "CONVERSATION": ConversationView(selection: selection)
        case "COUNT21": CountTo21View(selection: selection)
        case "TICTACTOE": TicTacToeView(selection: selection)
        case "WORDSEARCH": WordSearchView(selection: selection)
        case "MAZE": MazeGameView(selection: selection)
        case "MEMORY": MemoryMatchView(selection: selection)
        case "SUDOKU": SudokuView(selection: selection)
        case "HANGMAN": HangmanView(selection: selection)
        case "RPS": RpsView(selection: selection)
        case "SPACE": SpaceExplorerView(selection: selection)
        case "JUNGLE": JungleRunView(selection: selection)
        case "OCEAN": OceanDiveView(selection: selection)
        case "SEQUENCE": MemorySequenceView(selection: selection)
        case "SLIDE": SlidePuzzleView(selection: selection)
        case "MOUNTAIN": MountainClimbView(selection: selection)
        case "DESERT": DesertTrekView(selection: selection)
        case "VOLCANO": VolcanoClimbView(selection: selection)
        case "ARCTIC": ArcticTrekView(selection: selection)
        case "SAVANNA": SavannaSafariView(selection: selection)
        case "CAVE": CaveExplorerView(selection: selection)
        case "SWAMP": SwampTrekView(selection: selection)
        case "STORM": StormChaseView(selection: selection)
        case "MATH": MathSprintView(roundSeconds: Int(selection.difficulty ?? "60") ?? 60)
        default: TicTacToeView(selection: selection)
        }
    }
}
