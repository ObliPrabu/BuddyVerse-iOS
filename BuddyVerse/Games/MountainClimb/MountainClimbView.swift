import SwiftUI

/// Mirrors MountainClimbActivity. A solo self-paced rhythm game instead of a
/// turn-based resource-mash: tap STEP at a steady pace to climb. Tap again
/// too soon and you're too exhausted to make progress; wait too long between
/// taps and a gust of wind knocks you back down. There's no external moving
/// element to react to (unlike Volcano's needle or Swamp's fill meter) - the
/// only thing being judged here is the rhythm of your own taps. Solo only -
/// this game never reads IS_BOT on Android either (see GameCatalog's
/// soloGamesWithNoBot), so there's no bot/pass-and-play branching here.
struct MountainClimbView: View {
    @StateObject private var vm: MountainClimbViewModel
    @EnvironmentObject private var router: Router

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: MountainClimbViewModel(difficulty: selection.difficulty ?? "EASY"))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Mountain Climb 🏔️")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Text("Tap STEP at a steady pace - not too fast, not too slow!")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: 0xFFEB3B))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text("Altitude: \(vm.height)m")
                .font(.system(size: 20))
                .foregroundColor(.white)

            Text(vm.paceMessage)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(minHeight: 24)
                .padding(.bottom, 20)

            Text("🧗")
                .font(.system(size: 60))
                .frame(width: 100, height: 100)
                .padding(.bottom, 40)

            Button {
                vm.onStepTapped()
            } label: {
                Text("STEP")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 80)
            .background(Color.white)
            .foregroundColor(Color(hex: 0x546E7A))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 50)

            Button("Back to Menu") { router.pop() }
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: 0xDDDDDD, opacity: 0.67))
                .foregroundColor(Color(hex: 0x333333))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x546E7A).ignoresSafeArea())
        .navigationTitle("Mountain Climb")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.stop() }
    }
}

@MainActor
final class MountainClimbViewModel: ObservableObject {
    @Published var height = 0
    @Published var paceMessage = " "

    private let difficulty: String
    private var lastTapTime: Date?
    private var hasTapped = false
    private var isStopped = false

    private let idealMinGapMs: Double
    private let idealMaxGapMs: Double
    private let windGustTimeoutMs: Double
    private var windGustGeneration = 0

    // HARD = a narrower ideal window and a shorter fuse before the wind
    // punishes hesitation; EASY = a wider window and more time to recover
    // between taps.
    init(difficulty: String) {
        self.difficulty = difficulty
        switch difficulty {
        case "HARD":
            idealMinGapMs = 450; idealMaxGapMs = 700; windGustTimeoutMs = 1600
        case "MEDIUM":
            idealMinGapMs = 400; idealMaxGapMs = 850; windGustTimeoutMs = 1900
        default: // EASY
            idealMinGapMs = 350; idealMaxGapMs = 1000; windGustTimeoutMs = 2400
        }
    }

    func onStepTapped() {
        let now = Date()
        cancelWindGust()

        if !hasTapped {
            hasTapped = true
            paceMessage = "Keep that pace going!"
        } else {
            let gapMs = now.timeIntervalSince(lastTapTime ?? now) * 1000
            if gapMs < idealMinGapMs {
                paceMessage = "Too fast - you're exhausted!"
            } else if gapMs <= idealMaxGapMs {
                let gain = Int.random(in: 8..<19)
                height += gain
                paceMessage = "Great pace! +\(gain)m"
            } else {
                let gain = Int.random(in: 1..<5)
                height += gain
                paceMessage = "A bit slow, but still climbing. +\(gain)m"
            }
        }
        lastTapTime = now
        scheduleWindGust()
    }

    private func scheduleWindGust() {
        windGustGeneration += 1
        let generation = windGustGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + windGustTimeoutMs / 1000) { [weak self] in
            guard let self, !self.isStopped, generation == self.windGustGeneration else { return }
            self.applyWindGust()
        }
    }

    private func cancelWindGust() {
        // Bumping the generation makes any in-flight gust closure a no-op
        // when it fires, the same effect as Android's handler.removeCallbacks.
        windGustGeneration += 1
    }

    private func applyWindGust() {
        let loss = Int.random(in: 10..<26)
        height = max(height - loss, 0)
        paceMessage = "A gust of wind knocked you back -\(loss)m!"
        if height == 0 {
            paceMessage = "Blown all the way down! Starting over."
            hasTapped = false
        }
    }

    func stop() { isStopped = true }
}
