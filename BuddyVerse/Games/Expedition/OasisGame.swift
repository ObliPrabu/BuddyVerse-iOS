import Foundation

/// Desert Oasis Race (mirrors OasisGame.kt): tap the left and right buttons one
/// after the other to make your camel run - the same side twice and it stumbles
/// for a moment. Two rival camels run at a steady pace. Be first to the oasis
/// before the sunset timer runs out. (No hearts.)
final class OasisGame: ArcadeBase {
    static let sunsetSeconds = 30.0
    static let step = 0.014

    private(set) var me = 0.0
    private(set) var rivals = [0.0, 0.0]
    private(set) var sunsetLeft = OasisGame.sunsetSeconds
    private(set) var stumble = 0.0
    private var lastSide = ""
    private let rivalSpeed: [Double]

    init(difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        let s = ArcadeDifficulty.speed(difficulty)
        rivalSpeed = [0.036 * s, 0.042 * s]
        super.init(difficulty: difficulty, startLives: -1, seed: seed)
    }

    override var goal: Int { 1 }
    override var goalLabel: String { "Oasis reached" }
    override var controls: [ArcadeControl] { [ArcadeControl(id: "left", label: "◀ LEFT"), ArcadeControl(id: "right", label: "RIGHT ▶")] }
    override var points: Int { status == .won ? 50 + Int(sunsetLeft) * 3 : Int(me * 40) }
    override var hud: String {
        stumble > 0 ? "Oops, you stumbled! 😵" : "Tap LEFT, RIGHT, LEFT, RIGHT... ☀️ \(max(Int(sunsetLeft), 0))s"
    }

    override func onControl(id: String, pressed: Bool) {
        guard pressed, status == .playing, id == "left" || id == "right", stumble <= 0 else { return }
        if id == lastSide {
            stumble = 0.7
            lastSide = ""
            return
        }
        lastSide = id
        me = min(me + OasisGame.step, 1)
        if me >= 1 { gain() }
    }

    override func step(dtMs: Int) {
        guard status == .playing else { return }
        let dt = Double(dtMs) / 1000
        stumble = max(stumble - dt, 0)
        sunsetLeft -= dt
        for i in rivals.indices { rivals[i] = min(rivals[i] + rivalSpeed[i] * dt, 1) }
        if rivals.contains(where: { $0 >= 1 }) { lose(); return }
        if sunsetLeft <= 0 { sunsetLeft = 0; lose() }
    }

    override func sprites() -> [ArcadeSprite] {
        [
            ArcadeSprite(emoji: "☀️", x: 0.85, y: 0.1, size: 0.14),
            ArcadeSprite(emoji: "🌴", x: 0.96, y: 0.3, size: 0.1),
            ArcadeSprite(emoji: "🌴", x: 0.96, y: 0.5, size: 0.1),
            ArcadeSprite(emoji: "🌴", x: 0.96, y: 0.7, size: 0.1),
            ArcadeSprite(emoji: "🐫", x: 0.06 + 0.78 * rivals[0], y: 0.3, size: 0.11),
            ArcadeSprite(emoji: "🐫", x: 0.06 + 0.78 * rivals[1], y: 0.5, size: 0.11),
            ArcadeSprite(emoji: "🐪", x: 0.06 + 0.78 * me, y: 0.7, size: 0.13, alpha: stumble > 0 ? 0.5 : 1),
        ]
    }
}
