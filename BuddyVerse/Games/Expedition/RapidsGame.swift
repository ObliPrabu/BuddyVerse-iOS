import Foundation

/// River Rapids (mirrors RapidsGame.kt): the current pushes the raft sideways,
/// first one bank then the other. Hold a paddle to fight it and dodge the rocks.
/// Three hearts; stay afloat for 30 seconds (30 metres) to reach the calm lake.
final class RapidsGame: ArcadeBase {
    final class Rock {
        let x: Double
        var y: Double
        init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    static let raftY = 0.84

    private(set) var raftX = 0.5
    private(set) var drift = 0.0
    var rocks: [Rock] = []
    /// Off only in tests, so a round can be survived without rocks.
    var spawnRocks = true
    private var time = 0.0
    private var metres = 0
    private var spawnIn = 1.2
    private var left = false
    private var right = false

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        super.init(difficulty: difficulty, startLives: 3, seed: seed)
    }

    override var goal: Int { 30 }
    override var goalLabel: String { "Metres" }
    override var controls: [ArcadeControl] {
        [ArcadeControl(id: "left", label: "◀ PADDLE", hold: true), ArcadeControl(id: "right", label: "PADDLE ▶", hold: true)]
    }
    override var hud: String {
        "Hold a paddle to fight the current \(drift > 0.02 ? "➡️" : (drift < -0.02 ? "⬅️" : "〰️")) and dodge the rocks!"
    }

    override func onControl(id: String, pressed: Bool) {
        if id == "left" { left = pressed }
        if id == "right" { right = pressed }
    }

    override func step(dtMs: Int) {
        guard status == .playing else { return }
        let dt = Double(dtMs) / 1000
        time += dt
        drift = 0.22 * speed * sin(time * 1.1)
        let paddle = ((right ? 1.0 : 0.0) - (left ? 1.0 : 0.0)) * 0.55
        raftX = min(max(raftX + (drift + paddle) * dt, 0.08), 0.92)

        if spawnRocks {
            spawnIn -= dt
            while spawnIn <= 0 {
                rocks.append(Rock(x: 0.1 + rng.double() * 0.8, y: -0.05))
                spawnIn += 0.9 / speed
            }
        }
        var keep: [Rock] = []
        for r in rocks {
            r.y += 0.33 * speed * dt
            if abs(r.x - raftX) < 0.085 && abs(r.y - RapidsGame.raftY) < 0.07 {
                loseLife()
                if status != .playing { rocks = keep; return }
            } else if r.y <= 1.08 {
                keep.append(r)
            }
        }
        rocks = keep
        while Int(time) > metres { metres += 1; gain() }
    }

    override func sprites() -> [ArcadeSprite] {
        var out: [ArcadeSprite] = []
        for i in 0..<4 {
            out.append(ArcadeSprite(emoji: "🌲", x: 0.03, y: 0.15 + Double(i) * 0.25, size: 0.09, alpha: 0.6))
            out.append(ArcadeSprite(emoji: "🌲", x: 0.97, y: 0.15 + Double(i) * 0.25, size: 0.09, alpha: 0.6))
        }
        for r in rocks { out.append(ArcadeSprite(emoji: "🪨", x: r.x, y: r.y, size: 0.1)) }
        out.append(ArcadeSprite(emoji: "🛶", x: raftX, y: RapidsGame.raftY, size: 0.13))
        return out
    }
}
