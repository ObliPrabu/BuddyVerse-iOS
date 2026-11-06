import Foundation

/// Pirate Island (mirrors PirateIslandGame.kt): dig for the treasure chest on a
/// 5x5 island. Every dig shows a number - how many traps are next to that
/// square - and a sparkle if the chest is next to it too. A trap costs a heart.
/// Find the chest to win; fewer digs and more hearts left mean more points.
final class PirateIslandGame: ArcadeBase {
    static let n = 5

    let chest: Int
    let traps: Set<Int>
    var revealed = Set<Int>()
    private(set) var digs = 0
    private var earned = 0

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        // The island is laid out before the base class starts, from its own copy of the seeded source.
        var layout = GameRng(seed: seed)
        let cells = PirateIslandGame.n * PirateIslandGame.n
        let chestCell = layout.int(cells)
        var t = Set<Int>()
        let wanted = difficulty == "HARD" ? 5 : 4
        while t.count < wanted {
            let c = layout.int(cells)
            if c != chestCell { t.insert(c) }
        }
        chest = chestCell
        traps = t
        super.init(difficulty: difficulty, startLives: 3, seed: seed)
    }

    override var goal: Int { 1 }
    override var goalLabel: String { "Chest found" }
    override var hud: String { "Tap sand to dig. Numbers count nearby traps \u{1F573}\u{FE0F}, \u{2728} means the chest is close! Digs: \(digs)" }
    override var points: Int { earned }

    func neighbours(_ i: Int) -> [Int] {
        let n = PirateIslandGame.n
        let r = i / n
        let c = i % n
        var out: [Int] = []
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let nr = r + dr
                let nc = c + dc
                if (0..<n).contains(nr) && (0..<n).contains(nc) { out.append(nr * n + nc) }
            }
        }
        return out
    }

    func trapsNear(_ i: Int) -> Int { neighbours(i).filter { traps.contains($0) }.count }
    func chestNear(_ i: Int) -> Bool { neighbours(i).contains(chest) }

    override func onTapArena(x: Double, y: Double) {
        let n = PirateIslandGame.n
        dig(ArcadeGrid.cellOf(y, n) * n + ArcadeGrid.cellOf(x, n))
    }

    func dig(_ i: Int) {
        guard status == .playing, !revealed.contains(i) else { return }
        revealed.insert(i)
        digs += 1
        if i == chest {
            earned = max(100 + lives * 20 - digs * 3, 10)
            gain()
        } else if traps.contains(i) {
            loseLife()
        }
    }

    override func sprites() -> [ArcadeSprite] {
        let n = PirateIslandGame.n
        var out: [ArcadeSprite] = []
        for i in 0..<(n * n) {
            let x = ArcadeGrid.centre(i % n, n)
            let y = ArcadeGrid.centre(i / n, n)
            if !revealed.contains(i) {
                out.append(ArcadeSprite(emoji: "\u{1F7EB}", x: x, y: y, size: 0.17))
            } else if i == chest {
                out.append(ArcadeSprite(emoji: "\u{1F9F0}", x: x, y: y, size: 0.15))
            } else if traps.contains(i) {
                out.append(ArcadeSprite(emoji: "\u{1F573}\u{FE0F}", x: x, y: y, size: 0.15))
            } else {
                out.append(ArcadeSprite(emoji: "\u{1F7E8}", x: x, y: y, size: 0.17))
                out.append(ArcadeSprite(emoji: String(trapsNear(i)), x: x, y: y, size: 0.1))
                if chestNear(i) { out.append(ArcadeSprite(emoji: "\u{2728}", x: x + 0.055, y: y - 0.055, size: 0.06)) }
            }
        }
        return out
    }
}
