import Foundation

/// Canyon Zipline (mirrors ZiplineGame.kt): you hang from one of three ziplines.
/// Coins and eagles slide down towards you; tap left or right to swap lines,
/// grab 15 coins to win, and every eagle you hit costs a heart.
final class ZiplineGame: ArcadeBase {
    enum Kind { case coin, eagle }
    final class Item {
        let lane: Int
        var y: Double
        let kind: Kind
        init(lane: Int, y: Double, kind: Kind) { self.lane = lane; self.y = y; self.kind = kind }
    }

    static let lanes: [Double] = [0.2, 0.5, 0.8]
    static let playerY = 0.82
    static let fallSpeed = 0.42

    private(set) var lane = 1
    var items: [Item] = []
    private var spawnIn = 0.6

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        super.init(difficulty: difficulty, startLives: 3, seed: seed)
    }

    override var goal: Int { 15 }
    override var goalLabel: String { "Coins" }
    override var hud: String { "Grab the coins \u{1FA99} and dodge the eagles \u{1F985}!" }
    override var controls: [ArcadeControl] { [ArcadeControl(id: "left", label: "\u{25C0}"), ArcadeControl(id: "right", label: "\u{25B6}")] }

    override func onControl(id: String, pressed: Bool) {
        guard pressed, status == .playing else { return }
        if id == "left" { lane = max(lane - 1, 0) }
        if id == "right" { lane = min(lane + 1, ZiplineGame.lanes.count - 1) }
    }

    override func onTapArena(x: Double, y: Double) {
        onControl(id: x < 0.5 ? "left" : "right", pressed: true)
    }

    override func step(dtMs: Int) {
        guard status == .playing else { return }
        let dt = Double(dtMs) / 1000
        spawnIn -= dt
        while spawnIn <= 0 {
            items.append(Item(lane: rng.int(ZiplineGame.lanes.count), y: -0.05, kind: chance(0.4) ? .eagle : .coin))
            spawnIn += 0.85 / speed
        }
        var keep: [Item] = []
        for item in items {
            item.y += ZiplineGame.fallSpeed * speed * dt
            if item.lane == lane && abs(item.y - ZiplineGame.playerY) < 0.07 {
                if item.kind == .coin { gain() } else { loseLife() }
                if status != .playing { items = keep; return }
            } else if item.y <= 1.08 {
                keep.append(item)
            }
        }
        items = keep
    }

    override func sprites() -> [ArcadeSprite] {
        items.map { ArcadeSprite(emoji: $0.kind == .coin ? "\u{1FA99}" : "\u{1F985}", x: ZiplineGame.lanes[$0.lane], y: $0.y, size: 0.1) }
            + [ArcadeSprite(emoji: "\u{1FA82}", x: ZiplineGame.lanes[lane], y: ZiplineGame.playerY, size: 0.13)]
    }
}
