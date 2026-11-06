import Foundation

/// Ancient Temple (mirrors TempleGame.kt): a stone door asks "what comes next?" -
/// a short pattern of symbols with the last one missing. Pick the right one of
/// three answers; five solved puzzles open the temple. A 60-second torch burns
/// the whole time and a wrong answer burns 5 more seconds. (No hearts.)
final class TempleGame: ArcadeBase {
    struct Puzzle {
        let kind: Int
        let shown: [String]
        let options: [String]
        let correct: Int
    }

    static let startSeconds = 60.0
    static let wrongPenalty = 5.0
    static let symbols = ["🔺", "🔵", "🟩", "⭐", "🌙", "🔶"]

    private(set) var timeLeft: Double
    private(set) var puzzle: Puzzle = Puzzle(kind: 0, shown: [], options: ["", "", ""], correct: 0)
    private var message = "Pick what comes next!"

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        timeLeft = TempleGame.startSeconds / ArcadeDifficulty.speed(difficulty)
        super.init(difficulty: difficulty, startLives: -1, seed: seed)
        puzzle = makePuzzle()
    }

    override var goal: Int { 5 }
    override var goalLabel: String { "Puzzles" }
    override var hud: String { "\(message)  ⏳ \(max(Int(timeLeft), 0))s" }
    override var controls: [ArcadeControl] {
        puzzle.options.enumerated().map { ArcadeControl(id: "opt\($0.offset)", label: $0.element) }
    }
    override var points: Int { score * 10 + (status == .won ? Int(timeLeft) : 0) }

    private func shuffled(_ a: [String]) -> [String] {
        var a = a
        var i = a.count - 1
        while i > 0 { a.swapAt(i, rng.int(i + 1)); i -= 1 }
        return a
    }

    func makePuzzle() -> Puzzle {
        let pool = shuffled(TempleGame.symbols)
        let a = pool[0], b = pool[1], c = pool[2]
        let kind = rng.int(4)
        let shown: [String], answer: String, wrong: [String]
        switch kind {
        case 0: shown = [a, b, a, b, a]; answer = b; wrong = [a, c]
        case 1: shown = [a, b, c, a, b]; answer = c; wrong = [a, b]
        case 2: shown = [a, a, b, b, a, a, b]; answer = b; wrong = [a, c]
        default:
            shown = [a, a + a, a + a + a]; answer = a + a + a + a
            wrong = [a + a + a + a + a, a + a]
        }
        let options = shuffled([answer] + wrong)
        return Puzzle(kind: kind, shown: shown, options: options, correct: options.firstIndex(of: answer) ?? 0)
    }

    override func onControl(id: String, pressed: Bool) {
        guard pressed, status == .playing, id.hasPrefix("opt"), let pick = Int(id.dropFirst(3)) else { return }
        if pick == puzzle.correct {
            message = "Correct! The door groans open a little more."
            gain()
            if status == .playing { puzzle = makePuzzle() }
        } else {
            message = "Not quite - the torch burns 5 seconds!"
            timeLeft -= TempleGame.wrongPenalty
            if timeLeft <= 0 { timeLeft = 0; lose() }
        }
    }

    override func step(dtMs: Int) {
        guard status == .playing else { return }
        timeLeft -= Double(dtMs) / 1000
        if timeLeft <= 0 { timeLeft = 0; lose() }
    }

    override func sprites() -> [ArcadeSprite] {
        let n = Double(puzzle.shown.count + 1)
        let widest = Double(puzzle.shown.map { $0.unicodeScalars.count }.max() ?? 1)
        let size = min(max(0.8 / n / widest, 0.05), 0.12)
        var out = [ArcadeSprite(emoji: "🏛️", x: 0.5, y: 0.2, size: 0.26)]
        for (i, s) in puzzle.shown.enumerated() {
            out.append(ArcadeSprite(emoji: s, x: (Double(i) + 0.5) / n, y: 0.6, size: size))
        }
        out.append(ArcadeSprite(emoji: "❓", x: (n - 0.5) / n, y: 0.6, size: 0.12))
        return out
    }
}
