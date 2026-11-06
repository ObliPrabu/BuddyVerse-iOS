import Foundation

/// Mars Rover (mirrors RoverGame.kt): tap DRIVE to roll along a track and SCOOP
/// when a rock sample is under the rover. Gather 5 samples before the battery or
/// the road runs out. Dust storms make each DRIVE tap go only about a third as far.
final class RoverGame: ArcadeBase {
    static let batterySeconds = 45.0
    static let scoopReach = 0.03

    private(set) var pos = 0.0
    private(set) var batteryLeft = RoverGame.batterySeconds
    private(set) var storm = false
    var samples: [Double] = [0.12, 0.24, 0.36, 0.48, 0.60, 0.72, 0.84, 0.94]
    private var stormTimer = 6.0
    private var driveStep: Double

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        driveStep = 0.02 / ArcadeDifficulty.speed(difficulty)
        super.init(difficulty: difficulty, startLives: -1, seed: seed)
    }

    override var goal: Int { 5 }
    override var goalLabel: String { "Samples" }
    override var controls: [ArcadeControl] {
        [ArcadeControl(id: "drive", label: "DRIVE 🚙"), ArcadeControl(id: "scoop", label: "SCOOP 🪨")]
    }
    override var points: Int { score * 20 + (status == .won ? Int(batteryLeft) : 0) }
    override var hud: String {
        (storm ? "Dust storm! 🌪️ Each tap goes less far." : "Tap DRIVE, and SCOOP when a 🪨 is under you!") + "  🔋 \(max(Int(batteryLeft), 0))s"
    }

    override func onControl(id: String, pressed: Bool) {
        guard pressed, status == .playing else { return }
        switch id {
        case "drive":
            pos = min(pos + driveStep * (storm ? 0.35 : 1), 1)
            if pos >= 1 { lose() }
        case "scoop":
            if let i = samples.firstIndex(where: { abs($0 - pos) <= RoverGame.scoopReach }) {
                samples.remove(at: i)
                gain()
            }
        default: break
        }
    }

    override func step(dtMs: Int) {
        guard status == .playing else { return }
        let dt = Double(dtMs) / 1000
        batteryLeft -= dt
        if batteryLeft <= 0 { batteryLeft = 0; lose(); return }
        stormTimer -= dt
        if stormTimer <= 0 {
            storm.toggle()
            stormTimer = storm ? 2.5 + rng.double() * 1.5 : 5 + rng.double() * 4
        }
    }

    override func sprites() -> [ArcadeSprite] {
        var out = [ArcadeSprite(emoji: "🪐", x: 0.82, y: 0.15, size: 0.14), ArcadeSprite(emoji: "🏁", x: 0.95, y: 0.64, size: 0.1)]
        for s in samples { out.append(ArcadeSprite(emoji: "🪨", x: 0.05 + 0.9 * s, y: 0.66, size: 0.07)) }
        out.append(ArcadeSprite(emoji: "🤖", x: 0.05 + 0.9 * pos, y: 0.56, size: 0.12))
        if storm {
            for i in 0..<5 {
                out.append(ArcadeSprite(emoji: "🌪️", x: 0.1 + Double(i) * 0.2, y: 0.3 + Double(i % 2) * 0.15, size: 0.14, alpha: 0.8))
            }
        }
        return out
    }
}
