import Foundation

/// Hot-Air Balloon (mirrors BalloonGame.kt): hold the burner to rise, let go to
/// sink. Fly through wind rings (1 point) and tap DROP when a village is under
/// the basket (2 points). Storm clouds and scraping the ground cost a heart.
/// Ten wind points win.
final class BalloonGame: ArcadeBase {
    final class Ring { var x: Double; let y: Double; init(x: Double, y: Double) { self.x = x; self.y = y } }
    final class Cloud { var x: Double; let y: Double; init(x: Double, y: Double) { self.x = x; self.y = y } }
    final class Village { var x: Double; var delivered = false; init(x: Double) { self.x = x } }

    static let balloonX = 0.3

    private(set) var alt = 0.5
    var rings: [Ring] = []
    var clouds: [Cloud] = []
    var villages: [Village] = []
    private var burner = false
    private var message = "Hold 🔥 to rise. Catch 💨 rings, dodge ⛈️, DROP 📦 on villages!"
    private var ringIn = 1.0
    private var cloudIn = 2.4
    private var villageIn = 2.8
    private var groundCooldown = 0.0

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        super.init(difficulty: difficulty, startLives: 3, seed: seed)
    }

    override var goal: Int { 10 }
    override var goalLabel: String { "Wind points" }
    override var controls: [ArcadeControl] {
        [ArcadeControl(id: "burner", label: "🔥 BURNER", hold: true), ArcadeControl(id: "drop", label: "📦 DROP")]
    }
    override var hud: String { message }

    override func onControl(id: String, pressed: Bool) {
        switch id {
        case "burner": burner = pressed
        case "drop": if pressed && status == .playing { dropSupplies() }
        default: break
        }
    }

    func dropSupplies() {
        if let v = villages.first(where: { !$0.delivered && abs($0.x - BalloonGame.balloonX) < 0.1 }) {
            v.delivered = true
            message = "Supplies delivered! +2"
            gain(2)
        } else {
            message = "No village below - save your supplies!"
        }
    }

    override func step(dtMs: Int) {
        guard status == .playing else { return }
        let dt = Double(dtMs) / 1000
        alt = min(max(alt + (burner ? -0.35 : 0.2) * dt, 0.08), 0.93)
        groundCooldown -= dt
        if alt >= 0.9 && groundCooldown <= 0 {
            groundCooldown = 1.2
            alt = 0.65
            message = "Bump! The basket scraped the ground."
            loseLife()
            if status != .playing { return }
        }

        ringIn -= dt; cloudIn -= dt; villageIn -= dt
        while ringIn <= 0 { rings.append(Ring(x: 1.1, y: 0.2 + rng.double() * 0.55)); ringIn += 1.4 / speed }
        while cloudIn <= 0 { clouds.append(Cloud(x: 1.1, y: 0.2 + rng.double() * 0.5)); cloudIn += 2.6 / speed }
        while villageIn <= 0 { villages.append(Village(x: 1.1)); villageIn += 3.2 / speed }

        let scroll = 0.25 * speed * dt
        for r in rings { r.x -= scroll }
        for c in clouds { c.x -= scroll }
        for v in villages { v.x -= scroll }

        var keepRings: [Ring] = []
        for r in rings {
            if abs(r.x - BalloonGame.balloonX) < 0.08 && abs(r.y - alt) < 0.1 {
                gain()
                if status != .playing { rings = keepRings; return }
            } else if r.x >= -0.1 { keepRings.append(r) }
        }
        rings = keepRings
        var keepClouds: [Cloud] = []
        for c in clouds {
            if abs(c.x - BalloonGame.balloonX) < 0.09 && abs(c.y - alt) < 0.1 {
                message = "Storm cloud! Hold on!"
                loseLife()
                if status != .playing { clouds = keepClouds; return }
            } else if c.x >= -0.1 { keepClouds.append(c) }
        }
        clouds = keepClouds
        villages.removeAll { $0.x < -0.1 }
    }

    override func sprites() -> [ArcadeSprite] {
        var out: [ArcadeSprite] = []
        for v in villages { out.append(ArcadeSprite(emoji: v.delivered ? "🏡" : "🏘️", x: v.x, y: 0.95, size: 0.11)) }
        for r in rings { out.append(ArcadeSprite(emoji: "💨", x: r.x, y: r.y, size: 0.1)) }
        for c in clouds { out.append(ArcadeSprite(emoji: "⛈️", x: c.x, y: c.y, size: 0.12)) }
        out.append(ArcadeSprite(emoji: "🎈", x: BalloonGame.balloonX, y: alt, size: 0.14))
        return out
    }
}
