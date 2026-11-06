import Foundation

/// Meteor Shower (mirrors MeteorGame.kt): steer a rocket along the bottom by
/// holding the left or right button. Stars fall for you to catch (12 to win) and
/// meteors fall for you to dodge - each one that hits costs a heart.
final class MeteorGame: ArcadeBase {
    final class Rock {
        var x: Double
        var y: Double
        let fall: Double
        let star: Bool
        init(x: Double, y: Double, fall: Double, star: Bool) { self.x = x; self.y = y; self.fall = fall; self.star = star }
    }

    static let minX = 0.06
    static let maxX = 0.94
    static let shipY = 0.88

    private(set) var shipX = 0.5
    var rocks: [Rock] = []
    private var left = false
    private var right = false
    private var spawnIn = 0.5

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        super.init(difficulty: difficulty, startLives: 3, seed: seed)
    }

    override var goal: Int { 12 }
    override var goalLabel: String { "Stars" }
    override var hud: String { "Hold \u{25C0} \u{25B6} to steer. Catch \u{2B50}, dodge \u{2604}\u{FE0F}!" }
    override var controls: [ArcadeControl] {
        [ArcadeControl(id: "left", label: "\u{25C0}", hold: true), ArcadeControl(id: "right", label: "\u{25B6}", hold: true)]
    }

    override func onControl(id: String, pressed: Bool) {
        if id == "left" { left = pressed }
        if id == "right" { right = pressed }
    }

    // A tap on the sky nudges the rocket half way towards it, for players who prefer tapping.
    override func onTapArena(x: Double, y: Double) {
        shipX = min(max(shipX + (x - shipX) * 0.5, MeteorGame.minX), MeteorGame.maxX)
    }

    override func step(dtMs: Int) {
        guard status == .playing else { return }
        let dt = Double(dtMs) / 1000
        let dir = (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0)
        shipX = min(max(shipX + dir * 0.7 * speed * dt, MeteorGame.minX), MeteorGame.maxX)

        spawnIn -= dt
        while spawnIn <= 0 {
            rocks.append(Rock(x: 0.08 + rng.double() * 0.84, y: -0.05, fall: (0.30 + rng.double() * 0.2) * speed, star: chance(0.45)))
            spawnIn += 0.55 / speed
        }
        var keep: [Rock] = []
        for r in rocks {
            r.y += r.fall * dt
            if abs(r.x - shipX) < 0.09 && abs(r.y - MeteorGame.shipY) < 0.07 {
                if r.star { gain() } else { loseLife() }
                if status != .playing { rocks = keep; return }
            } else if r.y <= 1.08 {
                keep.append(r)
            }
        }
        rocks = keep
    }

    override func sprites() -> [ArcadeSprite] {
        rocks.map { ArcadeSprite(emoji: $0.star ? "\u{2B50}" : "\u{2604}\u{FE0F}", x: $0.x, y: $0.y, size: 0.1) }
            + [ArcadeSprite(emoji: "\u{1F680}", x: shipX, y: MeteorGame.shipY, size: 0.13)]
    }
}
