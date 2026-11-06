import Foundation

/// Dino Valley (mirrors DinoValleyGame.kt): a turn-based walk on a 5x5 valley.
/// Collect all five eggs. After each of your steps the friendly dinosaurs wander
/// one step; if one bumps into you it nudges you back to the start (and costs a
/// heart), no harm done.
final class DinoValleyGame: ArcadeBase {
    final class Pos {
        var r: Int
        var c: Int
        init(_ r: Int, _ c: Int) { self.r = r; self.c = c }
    }

    static let n = 5
    static let eggCount = 5
    private static let calmMessage = "Collect every egg \u{1F95A}. The dinosaurs \u{1F995} are friendly, but they bump!"

    private(set) var playerR = DinoValleyGame.n - 1
    private(set) var playerC = 0
    var eggs: [Pos] = []
    var dinos: [Pos] = []
    private var message = DinoValleyGame.calmMessage

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        super.init(difficulty: difficulty, startLives: 3, seed: seed)
        func free(_ game: DinoValleyGame) -> Pos {
            while true {
                let p = Pos(game.rng.int(DinoValleyGame.n), game.rng.int(DinoValleyGame.n))
                let startCell = p.r == DinoValleyGame.n - 1 && p.c == 0
                if !startCell && !game.eggs.contains(where: { $0.r == p.r && $0.c == p.c })
                    && !game.dinos.contains(where: { $0.r == p.r && $0.c == p.c }) { return p }
            }
        }
        for _ in 0..<DinoValleyGame.eggCount { eggs.append(free(self)) }
        for _ in 0..<(difficulty == "HARD" ? 3 : 2) { dinos.append(free(self)) }
    }

    override var goal: Int { DinoValleyGame.eggCount }
    override var goalLabel: String { "Eggs" }
    override var hud: String { message }
    override var controls: [ArcadeControl] {
        [ArcadeControl(id: "up", label: "\u{2B06}\u{FE0F}"), ArcadeControl(id: "down", label: "\u{2B07}\u{FE0F}"),
         ArcadeControl(id: "left", label: "\u{2B05}\u{FE0F}"), ArcadeControl(id: "right", label: "\u{27A1}\u{FE0F}")]
    }

    override func onControl(id: String, pressed: Bool) {
        guard pressed else { return }
        switch id {
        case "up": move(-1, 0)
        case "down": move(1, 0)
        case "left": move(0, -1)
        case "right": move(0, 1)
        default: break
        }
    }

    // Tapping a square next to you walks there.
    override func onTapArena(x: Double, y: Double) {
        let r = ArcadeGrid.cellOf(y, DinoValleyGame.n)
        let c = ArcadeGrid.cellOf(x, DinoValleyGame.n)
        if abs(r - playerR) + abs(c - playerC) == 1 { move(r - playerR, c - playerC) }
    }

    func move(_ dr: Int, _ dc: Int) {
        guard status == .playing else { return }
        let nr = playerR + dr
        let nc = playerC + dc
        guard (0..<DinoValleyGame.n).contains(nr), (0..<DinoValleyGame.n).contains(nc) else { return }
        playerR = nr
        playerC = nc
        message = DinoValleyGame.calmMessage
        if let i = eggs.firstIndex(where: { $0.r == playerR && $0.c == playerC }) {
            eggs.remove(at: i)
            gain()
            if status != .playing { return }
        }
        if bumped() { return }
        for d in dinos { wander(d) }
        _ = bumped()
    }

    private func wander(_ d: Pos) {
        let options = [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]
            .map { Pos(d.r + $0.0, d.c + $0.1) }
            .filter { (0..<DinoValleyGame.n).contains($0.r) && (0..<DinoValleyGame.n).contains($0.c) }
        let pick = options[rng.int(options.count)]
        d.r = pick.r
        d.c = pick.c
    }

    // A dinosaur on your square nudges you back to the start.
    private func bumped() -> Bool {
        guard dinos.contains(where: { $0.r == playerR && $0.c == playerC }) else { return false }
        playerR = DinoValleyGame.n - 1
        playerC = 0
        message = "A friendly dino bumped you back to the start!"
        loseLife()
        return true
    }

    override func sprites() -> [ArcadeSprite] {
        let n = DinoValleyGame.n
        var out: [ArcadeSprite] = []
        for r in 0..<n { for c in 0..<n { out.append(ArcadeSprite(emoji: "\u{1F33F}", x: ArcadeGrid.centre(c, n), y: ArcadeGrid.centre(r, n), size: 0.17, alpha: 0.3)) } }
        for e in eggs { out.append(ArcadeSprite(emoji: "\u{1F95A}", x: ArcadeGrid.centre(e.c, n), y: ArcadeGrid.centre(e.r, n), size: 0.14)) }
        for d in dinos { out.append(ArcadeSprite(emoji: "\u{1F995}", x: ArcadeGrid.centre(d.c, n), y: ArcadeGrid.centre(d.r, n), size: 0.16)) }
        out.append(ArcadeSprite(emoji: "\u{1F9D2}", x: ArcadeGrid.centre(playerC, n), y: ArcadeGrid.centre(playerR, n), size: 0.15))
        return out
    }
}
