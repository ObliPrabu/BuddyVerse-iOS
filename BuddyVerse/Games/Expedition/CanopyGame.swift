import Foundation

/// Rainforest Canopy (mirrors CanopyGame.kt): you hang on a vine that swings from
/// side to side. Tap to let go - you fly on in the direction you were swinging
/// and land somewhere along the treetops. Land on the next branch to score; a
/// miss is a fall (a heart). Eight branches win. A little 🎯 shows where you
/// would land, so the timing is a skill, not a guess.
final class CanopyGame: ArcadeBase {
    /// Swing phase; the vine's angle is sin(phase), -1 (far left) to 1 (far right).
    var phase = 0.0
    private(set) var target = 0.75
    let tolerance: Double
    private var message = "Tap LET GO so the 🎯 lands on the green branch!"
    private var flightLeft = 0.0

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        tolerance = difficulty == "HARD" ? 0.06 : (difficulty == "MEDIUM" ? 0.075 : 0.09)
        super.init(difficulty: difficulty, startLives: 3, seed: seed)
    }

    override var goal: Int { 8 }
    override var goalLabel: String { "Branches" }
    override var controls: [ArcadeControl] { [ArcadeControl(id: "jump", label: "LET GO 🐒")] }
    override var hud: String { message }

    /// Puts the branch somewhere exact (tests only).
    func moveTargetForTest(_ x: Double) { target = x }

    /// Where you would land if you let go right now (0...1 across the screen).
    func landing() -> Double {
        let dir = cos(phase) >= 0 ? 1.0 : -1.0
        return 0.5 + 0.4 * sin(phase) + 0.25 * dir
    }

    override func onControl(id: String, pressed: Bool) {
        guard pressed, status == .playing, id == "jump", flightLeft <= 0 else { return }
        if abs(landing() - target) <= tolerance {
            message = "Great jump!"
            gain()
            if status == .playing { newTarget() }
        } else {
            message = "Splash! You missed the branch."
            loseLife()
        }
        flightLeft = 0.5   // a short pause so a double tap cannot count twice
    }

    private func newTarget() {
        var t = 0.0
        repeat { t = 0.2 + rng.double() * 0.6 } while abs(t - target) < 0.15
        target = t
    }

    override func step(dtMs: Int) {
        guard status == .playing else { return }
        let dt = Double(dtMs) / 1000
        flightLeft = max(flightLeft - dt, 0)
        phase += 2.2 * speed * dt
    }

    override func sprites() -> [ArcadeSprite] {
        let ax = 0.5 + 0.4 * sin(phase)
        // The monkey hangs lowest at the middle of the swing and rises a little at each end.
        let ay = 0.12 + 0.3 * (1 - 0.3 * abs(sin(phase)))
        return [
            ArcadeSprite(emoji: "🌿", x: target, y: 0.8, size: 0.14),
            ArcadeSprite(emoji: "🎯", x: min(max(landing(), 0.03), 0.97), y: 0.8, size: 0.07, alpha: 0.8),
            ArcadeSprite(emoji: "🌳", x: 0.5, y: 0.05, size: 0.1),
            ArcadeSprite(emoji: "🐒", x: ax, y: ay + 0.1, size: 0.13),
        ]
    }
}
