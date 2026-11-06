import Foundation

// The shared core of the "expedition" mini-games added in 2026-11, mirroring
// ArcadeCore.kt on Android (Canyon Zipline, Meteor Shower, Dino Valley, Pirate
// Island and the rest of the batch). All of a game's rules live in a small
// plain-Swift class (so they can be unit tested without SwiftUI) that hands the
// screen a list of emoji "sprites" to draw. ExpeditionView does everything
// else: the score line, best score, hearts, win/lose overlay, confetti,
// pausing and the Back/Home/Feedback/Report buttons. This file only imports
// Foundation on purpose. Names that could clash with SwiftUI (Grid, Control,
// Sprite) carry an "Arcade" prefix here; Android uses the bare names.

enum GameStatus { case playing, won, lost }

/// One emoji drawn on the square play area. x and y run 0...1 across the area; size is a fraction of its width.
struct ArcadeSprite {
    let emoji: String
    let x: Double
    let y: Double
    var size: Double = 0.1
    var alpha: Double = 1
}

/// A button under the play area. A `hold` control reports press and release (steering); any other reports one tap.
struct ArcadeControl: Equatable {
    let id: String
    let label: String
    var hold: Bool = false
}

protocol ArcadeGame: AnyObject {
    /// The buttons to show right now (a puzzle game changes them for every question).
    var controls: [ArcadeControl] { get }
    /// What the progress counts, for the score line: "Coins", "Stars", "Eggs"...
    var goalLabel: String { get }
    var goal: Int { get }
    var score: Int { get }
    /// Hearts left, or -1 if this game has no lives.
    var lives: Int { get }
    var status: GameStatus { get }
    /// One line of instructions or news, shown above the play area.
    var hud: String { get }
    /// What is saved as the personal best (usually the score).
    var points: Int { get }
    func step(dtMs: Int)
    func sprites() -> [ArcadeSprite]
    func onControl(id: String, pressed: Bool)
    func onTapArena(x: Double, y: Double)
}

enum ArcadeDifficulty {
    /// One number every game scales its speeds with.
    static func speed(_ difficulty: String) -> Double {
        switch difficulty {
        case "HARD": return 1.4
        case "MEDIUM": return 1.2
        default: return 1
        }
    }
}

enum ArcadeGrid {
    /// Middle of cell `i` of `n` along one axis, as 0...1.
    static func centre(_ i: Int, _ n: Int) -> Double { (Double(i) + 0.5) / Double(n) }
    /// Which cell of `n` the 0...1 position `v` is in.
    static func cellOf(_ v: Double, _ n: Int) -> Int { min(max(Int(v * Double(n)), 0), n - 1) }
}

/// A small seedable random source (SplitMix64) so a game's rules can be tested with a fixed seed.
struct GameRng {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// A whole number 0..<n.
    mutating func int(_ n: Int) -> Int { Int(nextUInt64() % UInt64(n)) }
    /// A number 0..<1.
    mutating func double() -> Double { Double(nextUInt64() >> 11) / 9007199254740992.0 }
    mutating func chance(_ p: Double) -> Bool { double() < p }
}

/// What nearly every game needs: score, lives, the win/lose state and a seedable random source.
class ArcadeBase: ArcadeGame {
    let difficulty: String
    var rng: GameRng
    let speed: Double

    private(set) var score = 0
    private(set) var lives: Int
    private(set) var status = GameStatus.playing

    init(difficulty: String, startLives: Int = 3, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.difficulty = difficulty
        self.lives = startLives
        self.rng = GameRng(seed: seed)
        self.speed = ArcadeDifficulty.speed(difficulty)
    }

    var goal: Int { 1 }
    var goalLabel: String { "Score" }
    var controls: [ArcadeControl] { [] }
    var hud: String { "" }
    var points: Int { score }

    final func gain(_ n: Int = 1) {
        score += n
        if score >= goal { win() }
    }

    final func win() {
        if status == .playing { status = .won }
    }

    final func lose() {
        if status == .playing { status = .lost }
    }

    final func loseLife() {
        if lives > 0 {
            lives -= 1
            if lives == 0 { lose() }
        }
    }

    final func chance(_ p: Double) -> Bool { rng.chance(p) }

    func step(dtMs: Int) {}
    func sprites() -> [ArcadeSprite] { [] }
    func onControl(id: String, pressed: Bool) {}
    func onTapArena(x: Double, y: Double) {}
}
