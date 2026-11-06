import Foundation

/// Shipwreck Dive (mirrors ShipwreckGame.kt): three chests hide on a 6x6 patch of
/// sea floor. Every tap spends one breath of air. A tap on a chest collects it;
/// any other tap sends a sonar ping showing how many steps away the nearest
/// chest still is. Collect all three before the air runs out. (No hearts.)
final class ShipwreckGame: ArcadeBase {
    static let n = 6

    private(set) var air: Int
    let chests: Set<Int>
    private(set) var found = Set<Int>()
    /// Squares already pinged, with the distance the sonar reported.
    private(set) var pings: [Int: Int] = [:]

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        air = difficulty == "HARD" ? 13 : (difficulty == "MEDIUM" ? 15 : 18)
        var rng = GameRng(seed: seed)
        var c = Set<Int>()
        while c.count < 3 { c.insert(rng.int(ShipwreckGame.n * ShipwreckGame.n)) }
        chests = c
        super.init(difficulty: difficulty, startLives: -1, seed: seed)
        self.rng = rng
    }

    override var goal: Int { 3 }
    override var goalLabel: String { "Chests" }
    override var hud: String { "Tap a square: 🔔 shows how far the nearest 🧰 is. Air: \(air) 🫧" }
    override var points: Int { score * 30 + (status == .won ? air * 5 : 0) }

    /// Steps (not diagonal) from square `i` to the nearest chest not yet collected.
    func distanceToNearest(_ i: Int) -> Int {
        let n = ShipwreckGame.n
        return chests.subtracting(found).map { abs($0 / n - i / n) + abs($0 % n - i % n) }.min() ?? 0
    }

    override func onTapArena(x: Double, y: Double) {
        let n = ShipwreckGame.n
        dive(ArcadeGrid.cellOf(y, n) * n + ArcadeGrid.cellOf(x, n))
    }

    func dive(_ i: Int) {
        guard status == .playing, !found.contains(i), pings[i] == nil else { return }
        air -= 1
        if chests.contains(i) {
            found.insert(i)
            gain()
        } else {
            pings[i] = distanceToNearest(i)
        }
        if status == .playing && air <= 0 { lose() }
    }

    override func sprites() -> [ArcadeSprite] {
        let n = ShipwreckGame.n
        var out: [ArcadeSprite] = []
        for i in 0..<(n * n) {
            let x = ArcadeGrid.centre(i % n, n)
            let y = ArcadeGrid.centre(i / n, n)
            if found.contains(i) {
                out.append(ArcadeSprite(emoji: "🧰", x: x, y: y, size: 0.13))
            } else if let d = pings[i] {
                out.append(ArcadeSprite(emoji: "🌊", x: x, y: y, size: 0.15, alpha: 0.5))
                out.append(ArcadeSprite(emoji: String(d), x: x, y: y, size: 0.09))
            } else {
                out.append(ArcadeSprite(emoji: "🟦", x: x, y: y, size: 0.15))
            }
        }
        out.append(ArcadeSprite(emoji: "🚢", x: 0.9, y: 0.04, size: 0.08))
        return out
    }
}
