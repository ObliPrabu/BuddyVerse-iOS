import Foundation
import SwiftUI

// Mirrors the "bag of Intent extras" every Android screen threads forward
// (GAME_TYPE/DIFFICULTY/IS_BOT/IS_NEARBY/MOOD/AGE_GROUP/WORD_MODE).
// Passed by value along `Router.path` instead of Intent extras - same idea
// (immutable state handed to the next screen), different plumbing.
struct GameSelection: Hashable {
    var gameType: String
    var difficulty: String? = nil
    var isBot: Bool = false
    var isNearby: Bool = false
    var mood: String? = nil
    var ageGroup: String? = nil
    var wordMode: String? = nil
    var premiumSource: String = "EXPEDITION"
    var players: [Player]? = nil
}

// Every screen BuddyVerse can navigate to. `Router.path` is just
// `[AppRoute]` (the app has no NavigationStack - see RootView), so
// `router.push(...)` is the direct equivalent of `startActivity(Intent(...))`
// and `router.pop()` (every screen's own Back button) is `finish()`.
enum AppRoute: Hashable {
    case mainWebsite
    case ageGroup(gameType: String, mood: String, difficulty: String)
    case moodSelection(gameType: String)
    case difficultySelection(gameType: String, mood: String)
    case aiGenerating(gameType: String, mood: String, ageGroup: String, difficulty: String)
    case onePhoneSelection(gameType: String)
    case friendTypeChoice(gameType: String)
    case botDifficulty(gameType: String)
    case comingSoon(gameName: String)
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
    case adminDashboard
    case getUpdates
    case dailyQuestion
}

// The single place that maps a GAME_TYPE string to its destination screen -
// mirrors InstructionsChoiceActivity.Companion.createGameIntent(), the one
// hub every flow funnels through before a game actually opens. Adding a new
// game means adding one case here and nowhere else.
@MainActor
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
        case "CHESS": ChessView(selection: selection)
        case "BALLOON": ExpeditionView(config: ExpeditionConfig(id: "BALLOON", title: "Hot-Air Balloon 🎈", background: Color(hex: 0x5C6BC0)), difficulty: selection.difficulty ?? "EASY") { BalloonGame(difficulty: $0) }
        case "RAPIDS": ExpeditionView(config: ExpeditionConfig(id: "RAPIDS", title: "River Rapids 🛶", background: Color(hex: 0x0277BD)), difficulty: selection.difficulty ?? "EASY") { RapidsGame(difficulty: $0) }
        case "ROVER": ExpeditionView(config: ExpeditionConfig(id: "ROVER", title: "Mars Rover 🤖", background: Color(hex: 0xBF360C)), difficulty: selection.difficulty ?? "EASY") { RoverGame(difficulty: $0) }
        case "TEMPLE": ExpeditionView(config: ExpeditionConfig(id: "TEMPLE", title: "Ancient Temple 🏛️", background: Color(hex: 0x8D6E63)), difficulty: selection.difficulty ?? "EASY") { TempleGame(difficulty: $0) }
        case "PIRATE": ExpeditionView(config: ExpeditionConfig(id: "PIRATE", title: "Pirate Island 🏴‍☠️", background: Color(hex: 0x00838F)), difficulty: selection.difficulty ?? "EASY") { PirateIslandGame(difficulty: $0) }
        case "DINO": ExpeditionView(config: ExpeditionConfig(id: "DINO", title: "Dino Valley 🦕", background: Color(hex: 0x2E7D32)), difficulty: selection.difficulty ?? "EASY") { DinoValleyGame(difficulty: $0) }
        case "METEOR": ExpeditionView(config: ExpeditionConfig(id: "METEOR", title: "Meteor Shower ☄️", background: Color(hex: 0x1A237E)), difficulty: selection.difficulty ?? "EASY") { MeteorGame(difficulty: $0) }
        case "ZIPLINE": ExpeditionView(config: ExpeditionConfig(id: "ZIPLINE", title: "Canyon Zipline 🪂", background: Color(hex: 0xE65100)), difficulty: selection.difficulty ?? "EASY") { ZiplineGame(difficulty: $0) }
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
        // An unknown game type used to silently open Tic-Tac-Toe, which hid a
        // mistyped or missing GAME_TYPE. Show an honest screen instead.
        default: ComingSoonView(gameName: selection.gameType)
        }
    }
}
