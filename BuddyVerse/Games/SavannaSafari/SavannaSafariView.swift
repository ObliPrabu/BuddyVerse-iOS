import SwiftUI

/// Mirrors SavannaSafariActivity: a go/no-go reaction game. A target animal
/// is picked once; the button's shown animal keeps auto-cycling on a timer.
/// Tapping while the target is showing scores a point, tapping any other
/// animal costs a strike, and either way the display jumps to a new animal
/// immediately after the tap (so you can't farm points by hammering a lucky
/// correct animal). Three strikes ends the round and rerolls the target.
struct SavannaSafariView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    @State private var score = 0
    @State private var strikes = 0
    @State private var targetAnimal = animals.randomElement()!
    @State private var currentAnimal = animals.randomElement()!
    @State private var statusText: String? // overrides the score line on game-over, like Android's tvScore reuse
    @State private var timer: Timer?

    private static let animals = ["🦁", "🐘", "🦒", "🦓", "🦏", "🐆", "🦛"]

    // How often the shown animal auto-cycles - shorter gaps mean less time
    // to notice and react to the target animal, which is what makes HARD
    // harder here.
    private var cycleInterval: TimeInterval {
        switch selection.difficulty {
        case "HARD": return 0.8
        case "MEDIUM": return 1.15
        default: return 1.5 // EASY (and default)
        }
    }

    private var scoreLine: String {
        statusText ?? "Spotted: \(score) | Strikes: \(strikes)/3"
    }

    var body: some View {
        ZStack {
            Color(hex: 0xF9A825).ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Savanna Safari")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                Text("Tap only when you see: \(targetAnimal)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: 0x3E2723))
                    .padding(.bottom, 10)

                Text(scoreLine)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: 0x3E2723))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 50)

                Button {
                    onAnimalTapped()
                } label: {
                    Text(currentAnimal)
                        .font(.system(size: 60))
                        .frame(width: 120, height: 120)
                        .background(Circle().fill(.white))
                }
                .padding(.bottom, 50)

                Text("Only tap for the target animal - wrong taps cost a strike!")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 50)

                Button("Back to Menu") { router.pop() }
                    // Android's backgroundTint is #AADDDDDD - alpha 0xAA (~0.667), not fully opaque.
                    .buttonStyle(LegacyBorderedButtonStyle(tint: Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)))
                    .foregroundColor(Color(hex: 0x333333))
            }
            .padding(20)
        }
        .onAppear { startCycling() }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func onAnimalTapped() {
        statusText = nil
        if currentAnimal == targetAnimal {
            score += 1
        } else {
            strikes += 1
        }

        if strikes >= 3 {
            statusText = "Game over! You spotted \(score) before 3 wrong taps."
            score = 0
            strikes = 0
            targetAnimal = Self.animals.randomElement()!
        }
        cycleAnimal()
    }

    private func startCycling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: cycleInterval, repeats: true) { _ in
            cycleAnimal()
        }
    }

    private func cycleAnimal() {
        currentAnimal = Self.animals.randomElement()!
    }
}
