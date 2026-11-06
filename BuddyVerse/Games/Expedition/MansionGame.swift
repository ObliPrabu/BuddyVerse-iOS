import Foundation

/// Haunted Mansion, the silly friendly kind (mirrors MansionGame.kt): a cheerful
/// ghost asks a riddle and you pick one of three answers. Five right answers
/// light up the house; each wrong answer blows out one of three candles.
/// Riddles do not repeat within a round.
final class MansionGame: ArcadeBase {
    struct Riddle {
        let question: String
        let answer: String
        let wrong1: String
        let wrong2: String
    }

    static let riddles: [Riddle] = [
        Riddle(question: "What kind of room has no doors or windows?", answer: "A mushroom", wrong1: "A bathroom", wrong2: "An attic"),
        Riddle(question: "What has hands but can't clap?", answer: "A clock", wrong1: "A ghost", wrong2: "A glove"),
        Riddle(question: "What gets wetter the more it dries?", answer: "A towel", wrong1: "A sponge", wrong2: "A cloud"),
        Riddle(question: "What do ghosts use to wash their hair?", answer: "Shamboo", wrong1: "Soap", wrong2: "Cobwebs"),
        Riddle(question: "Where do ghosts buy their snacks?", answer: "The ghost-ery store", wrong1: "The bakery", wrong2: "The library"),
        Riddle(question: "What is a ghost's favourite pudding?", answer: "Boo-nilla ice cream", wrong1: "Chocolate cake", wrong2: "Apple pie"),
        Riddle(question: "What can you catch but never throw?", answer: "A cold", wrong1: "A ball", wrong2: "A frisbee"),
        Riddle(question: "What has a neck but no head?", answer: "A bottle", wrong1: "A giraffe", wrong2: "A broom"),
        Riddle(question: "What kind of music do mummies like best?", answer: "Wrap music", wrong1: "Rock music", wrong2: "Jazz"),
        Riddle(question: "What do you call a ghost's little mistake?", answer: "A boo-boo", wrong1: "A slip-up", wrong2: "A whoops"),
        Riddle(question: "What has four legs but cannot walk?", answer: "A table", wrong1: "A dog", wrong2: "A spider"),
        Riddle(question: "What runs all day but never gets tired?", answer: "A river", wrong1: "A dog", wrong2: "A shoe"),
        Riddle(question: "What belongs to you but other people use it more?", answer: "Your name", wrong1: "Your hat", wrong2: "Your bed"),
        Riddle(question: "What goes up when the rain comes down?", answer: "An umbrella", wrong1: "A kite", wrong2: "A cat"),
        Riddle(question: "What do skeletons say before dinner?", answer: "Bone appetit!", wrong1: "Let's eat!", wrong2: "Yum!"),
        Riddle(question: "What building has the most stories?", answer: "The library", wrong1: "A garage", wrong2: "A shed"),
    ]

    private var bag: [Riddle] = []
    private(set) var current: Riddle = MansionGame.riddles[0]
    private(set) var options: [String] = []
    var correctIndex: Int { options.firstIndex(of: current.answer) ?? 0 }

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        super.init(difficulty: difficulty, startLives: 3, seed: seed)
        bag = shuffled(MansionGame.riddles)
        next()
    }

    override var goal: Int { 5 }
    override var goalLabel: String { "Riddles" }
    override var hud: String { "👻 \(current.question)" }
    override var controls: [ArcadeControl] {
        options.enumerated().map { ArcadeControl(id: "opt\($0.offset)", label: $0.element) }
    }

    private func shuffled<T>(_ a: [T]) -> [T] {
        var a = a
        var i = a.count - 1
        while i > 0 { a.swapAt(i, rng.int(i + 1)); i -= 1 }
        return a
    }

    private func next() {
        if bag.isEmpty { bag = shuffled(MansionGame.riddles) }
        current = bag.removeFirst()
        options = shuffled([current.answer, current.wrong1, current.wrong2])
    }

    override func onControl(id: String, pressed: Bool) {
        guard pressed, status == .playing, id.hasPrefix("opt"), let pick = Int(id.dropFirst(3)),
              options.indices.contains(pick) else { return }
        if pick == correctIndex { gain() } else { loseLife() }
        if status == .playing { next() }
    }

    override func sprites() -> [ArcadeSprite] {
        var out = [ArcadeSprite(emoji: "🏚️", x: 0.5, y: 0.45, size: 0.4), ArcadeSprite(emoji: "👻", x: 0.5, y: 0.3, size: 0.2)]
        for i in 0..<3 {
            out.append(ArcadeSprite(emoji: i < lives ? "🕯️" : "💨", x: 0.3 + Double(i) * 0.2, y: 0.85, size: 0.12, alpha: i < lives ? 1 : 0.5))
        }
        return out
    }
}
