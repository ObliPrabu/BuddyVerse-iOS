import SwiftUI

/// Mirrors JungleRunActivity: a fruit button jumps to a random spot on a
/// repeating timer (and also immediately whenever you land a tap on it),
/// racking up a running "fruits eaten" score. No bot, no nearby mode.
struct JungleRunView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    @State private var score = 0
    @State private var currentFruit = fruits.randomElement()!
    @State private var fruitPosition: CGPoint = CGPoint(x: 0, y: 0)
    @State private var hasPlacedFruit = false
    @State private var timer: Timer?
    @State private var showFeedback = false
    @State private var showReport = false

    private static let fruits = ["🍎", "🍌", "🍍", "🥭", "🍒"]

    // How often the fruit jumps to a new spot - shorter gaps mean less time
    // to react before it moves again, which is what makes HARD harder here.
    private var moveInterval: TimeInterval {
        switch selection.difficulty {
        case "HARD": return 0.8
        case "MEDIUM": return 1.15
        default: return 1.5 // EASY (and default)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0x2E7D32).ignoresSafeArea()

                Button {
                    score += 1
                    moveFruit(in: geo.size)
                } label: {
                    Text(currentFruit)
                        .font(.system(size: 60))
                        .frame(width: 120, height: 120)
                        .background(Circle().fill(.white))
                }
                .position(hasPlacedFruit ? fruitPosition : CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))

                VStack {
                    Text("Jungle Run")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)

                    Text("Fruits Eaten: \(score)")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: 0xFFEB3B))
                        .padding(.top, 10)

                    Spacer()

                    Text("Catch the fruit before it moves!")
                        .foregroundColor(.white)
                        .padding(.bottom, 30)

                    HStack(spacing: 10) {
                        Button("Back to Menu") { router.pop() }
                        Button("Home") { router.popToRoot() }
                    }
                    // Android's backgroundTint is #AADDDDDD - alpha 0xAA (~0.667), not fully opaque.
                    .buttonStyle(LegacyBorderedButtonStyle(tint: Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)))
                    .foregroundColor(Color(hex: 0x333333))

                    HStack(spacing: 10) {
                        Button("Feedback") { showFeedback = true }
                        Button("Report") { showReport = true }
                    }
                    .buttonStyle(LegacyBorderedButtonStyle(tint: Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)))
                    .foregroundColor(Color(hex: 0x333333))
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .onAppear {
                fruitPosition = randomFruitPosition(in: geo.size)
                hasPlacedFruit = true
                startMovement(in: geo.size)
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "JUNGLE") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "JUNGLE") }
    }

    private func startMovement(in size: CGSize) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: moveInterval, repeats: true) { _ in
            moveFruit(in: size)
        }
    }

    private func moveFruit(in size: CGSize) {
        fruitPosition = randomFruitPosition(in: size)
        currentFruit = Self.fruits.randomElement()!
    }

    // Guards against the narrow-screen "empty range" crash the Android
    // version had to special-case: clamp the upper bound so it never falls
    // below the lower bound, however small the available space is.
    private func randomFruitPosition(in size: CGSize) -> CGPoint {
        let minX: CGFloat = 70
        let maxX = max(minX + 1, size.width - 70)
        let minY: CGFloat = 160
        let maxY = max(minY + 1, size.height - 160)
        return CGPoint(x: .random(in: minX...maxX), y: .random(in: minY...maxY))
    }
}
