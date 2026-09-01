import SwiftUI

/// Mirrors SpaceExplorerActivity: touch anywhere on screen to move the
/// rocket there, and catching the star (landing within `catchRadius` of it)
/// scores a point and respawns the star at a new random spot. No bot, no
/// nearby mode - solo, untimed score attempt.
struct SpaceExplorerView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    @State private var score = 0
    @State private var shipPosition: CGPoint = CGPoint(x: 0, y: 0)
    @State private var starPosition: CGPoint = CGPoint(x: 0, y: 0)
    @State private var hasPlacedShip = false

    // How close a tap has to land to the star to count as a catch. A bigger
    // hitbox is more forgiving (EASY); a smaller one demands a precise tap (HARD).
    private var catchRadius: CGFloat {
        switch selection.difficulty {
        case "HARD": return 45
        case "MEDIUM": return 65
        default: return 85 // EASY (and default)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0x1A237E).ignoresSafeArea()

                Text("🚀")
                    .font(.system(size: 40))
                    .position(hasPlacedShip ? shipPosition : CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))

                Text("⭐")
                    .font(.system(size: 30))
                    .position(starPosition)

                VStack {
                    Text("Space Explorer")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)

                    Text("Star Score: \(score)")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: 0xFFEB3B))
                        .padding(.top, 5)

                    Spacer()

                    Text("Tap to Move the Rocket!")
                        .foregroundColor(.white)

                    HStack(spacing: 10) {
                        Button("Back") { router.pop() }
                        Button("Home") { router.popToRoot() }
                    }
                        .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0x757575)))
                        .foregroundColor(.white)
                        .padding(.bottom, 30)
                        .padding(.top, 12)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                // Fires on touch-down and follows the finger while dragging,
                // matching the Android version's ACTION_DOWN "move ship to
                // touch point" behavior (and feels natural for "touch
                // anywhere to move" instead of requiring a discrete tap).
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        moveShip(to: value.location, in: geo.size)
                    }
            )
            .onAppear {
                starPosition = randomStarPosition(in: geo.size)
            }
        }
    }

    private func moveShip(to point: CGPoint, in size: CGSize) {
        shipPosition = point
        hasPlacedShip = true
        checkCollision(in: size)
    }

    private func checkCollision(in size: CGSize) {
        if abs(shipPosition.x - starPosition.x) < catchRadius && abs(shipPosition.y - starPosition.y) < catchRadius {
            score += 1
            starPosition = randomStarPosition(in: size)
        }
    }

    // Guards against the narrow-screen "empty range" crash the Android
    // version had to work around: if the available width/height is smaller
    // than the margins, `lower...upper` would have lower > upper. Clamping
    // the upper bound to never fall below the lower bound keeps this safe
    // on any screen size (including compact/split-screen iPad layouts).
    private func randomStarPosition(in size: CGSize) -> CGPoint {
        let minX: CGFloat = 40
        let maxX = max(minX + 1, size.width - 60)
        let minY: CGFloat = 140
        let maxY = max(minY + 1, size.height - 180)
        return CGPoint(x: .random(in: minX...maxX), y: .random(in: minY...maxY))
    }
}
