import SwiftUI

/// Mirrors StormChaseActivity: a Simon-says memory game. The storm "strikes"
/// a growing sequence across a 2x2 grid of quadrants, then you tap them back
/// in the same order. A fixed 20-round chase split into four zones that speed
/// up the flashes, a 3-point nerve meter (a miss retries the same round; only
/// running out of nerve falls back to the current zone's start), a perfect
/// streak counter, a persisted best round per difficulty, and a confetti
/// finish when round 20 is cleared. No bot, no nearby mode.
struct StormChaseView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    private struct Zone {
        let name: String
        let startRound: Int
        let endRound: Int
        let bgColor: UInt32
        let flashSpeedMultiplier: Double
    }

    private static let zones: [Zone] = [
        Zone(name: "Distant Rumble", startRound: 1, endRound: 5, bgColor: 0x37474F, flashSpeedMultiplier: 1.0),
        Zone(name: "Approaching Storm", startRound: 6, endRound: 10, bgColor: 0x2E3B41, flashSpeedMultiplier: 0.8),
        Zone(name: "Eye of the Storm", startRound: 11, endRound: 15, bgColor: 0x263238, flashSpeedMultiplier: 0.65),
        Zone(name: "Superstorm", startRound: 16, endRound: 20, bgColor: 0x1A2327, flashSpeedMultiplier: 0.5)
    ]
    private static let finishRound = 20

    @State private var sequence: [Int] = []
    @State private var inputIndex = 0
    @State private var round = 1
    @State private var nerve = 3
    @State private var usedRetryThisRound = false
    @State private var perfectStreak = 0
    @State private var bestRound = 0
    @State private var finished = false
    @State private var acceptingInput = false
    @State private var statusText = "Watch the storm's path..."
    @State private var highlightedQuadrant: Int?
    // Bumped every time a fresh round starts (or the view disappears), so
    // stale delayed callbacks from a superseded sequence no-op - the Swift
    // equivalent of Android's handler.removeCallbacksAndMessages(null).
    @State private var generation = 0
    @State private var showFeedback = false
    @State private var showReport = false

    private static let quadrantSymbols = ["⚡", "🌩️", "⛈️", "🌧️"]
    private static let quadrantColor = Color(hex: 0x607D8B)
    private static let highlightColor = Color(hex: 0xFFEB3B)

    private var difficulty: String { selection.difficulty ?? "EASY" }
    private var bestKey: String { "storm_best_\(difficulty)" }

    private func zoneForRound(_ r: Int) -> Zone {
        Self.zones.last(where: { r >= $0.startRound }) ?? Self.zones[0]
    }

    // Zone-1 baseline flash time: shorter flashes make HARD harder. Later
    // zones scale it down via Zone.flashSpeedMultiplier.
    private var baseFlashDuration: Double {
        switch difficulty {
        case "HARD": return 0.3
        case "MEDIUM": return 0.42
        default: return 0.55 // EASY (and default)
        }
    }

    private var flashDuration: TimeInterval {
        let ms = Int(baseFlashDuration * 1000 * zoneForRound(round).flashSpeedMultiplier)
        return Double(max(ms, 120)) / 1000
    }

    var body: some View {
        let zone = zoneForRound(round)
        ZStack {
            Color(hex: zone.bgColor).ignoresSafeArea()

            VStack(spacing: 0) {
                Text(zone.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)

                Text(statusText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFEB3B))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.bottom, 8)

                Text("Round: \(min(round, Self.finishRound)) / \(Self.finishRound)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text("Best: Round \(bestRound)")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xCFD8DC))
                    .padding(.bottom, 8)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Text("⚡")
                            .font(.system(size: 22))
                            .opacity(index < nerve ? 1.0 : 0.25)
                    }
                }
                .padding(.bottom, 4)

                Text("🔥 Perfect Streak x\(max(perfectStreak, 3))!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFD54F))
                    .opacity(perfectStreak >= 3 ? 1 : 0)
                    .padding(.bottom, 8)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        quadrantButton(0)
                        quadrantButton(1)
                    }
                    HStack(spacing: 8) {
                        quadrantButton(2)
                        quadrantButton(3)
                    }
                }
                .frame(width: 280, height: 280)
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

                Spacer(minLength: 0)
            }
            .padding(20)

            if finished {
                VStack(spacing: 0) {
                    Text("⚡ Storm Conquered!")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)

                    Text("Best: Round \(bestRound)")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: 0xFFD54F))
                        .padding(.bottom, 24)

                    Button("Chase Again") { restartChase() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: 0x37474F))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.8).ignoresSafeArea())
            }
        }
        .confettiOverlay(confetti)
        .onAppear {
            bestRound = UserDefaults.standard.integer(forKey: bestKey)
            if !finished && sequence.isEmpty { startRound(growSequence: true) }
        }
        .onDisappear { generation += 1 }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "STORM") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "STORM") }
    }

    @ViewBuilder
    private func quadrantButton(_ index: Int) -> some View {
        Button {
            onQuadrantTapped(index)
        } label: {
            Text(Self.quadrantSymbols[index])
                .font(.system(size: 36))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(highlightedQuadrant == index ? Self.highlightColor : Self.quadrantColor)
                .cornerRadius(8)
        }
        .padding(4)
    }

    private func startRound(growSequence: Bool) {
        generation += 1
        let myGeneration = generation
        acceptingInput = false
        inputIndex = 0
        if growSequence {
            // Only a genuinely new round clears the "used a retry" flag;
            // replaying after a miss must not erase that a retry happened.
            usedRetryThisRound = false
            sequence.append(Int.random(in: 0..<4))
        }
        statusText = "Watch the storm's path..."

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard myGeneration == generation else { return }
            playSequence(0, generation: myGeneration)
        }
    }

    private func playSequence(_ step: Int, generation myGeneration: Int) {
        guard myGeneration == generation else { return }
        guard step < sequence.count else {
            acceptingInput = true
            statusText = "Now repeat it!"
            return
        }
        let quadrantIndex = sequence[step]
        highlightedQuadrant = quadrantIndex
        DispatchQueue.main.asyncAfter(deadline: .now() + flashDuration) {
            guard myGeneration == generation else { return }
            highlightedQuadrant = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard myGeneration == generation else { return }
                playSequence(step + 1, generation: myGeneration)
            }
        }
    }

    private func onQuadrantTapped(_ index: Int) {
        guard acceptingInput, inputIndex < sequence.count else { return }
        let myGeneration = generation

        if index == sequence[inputIndex] {
            inputIndex += 1
            if inputIndex == sequence.count {
                acceptingInput = false
                if !usedRetryThisRound {
                    perfectStreak += 1
                } else {
                    perfectStreak = 0
                }

                let previousZone = zoneForRound(round).name
                round += 1
                if round > bestRound {
                    bestRound = round - 1
                    saveBest()
                }

                if round > Self.finishRound {
                    finishChase()
                    return
                }

                let newZone = zoneForRound(round)
                if newZone.name != previousZone {
                    nerve = 3 // reaching a new zone is itself a checkpoint - full nerve refill
                    statusText = "Entering \(newZone.name)! Nerve refilled."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        guard myGeneration == generation else { return }
                        startRound(growSequence: true)
                    }
                } else {
                    statusText = "Nice! Next round..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        guard myGeneration == generation else { return }
                        startRound(growSequence: true)
                    }
                }
            }
        } else {
            acceptingInput = false
            usedRetryThisRound = true
            perfectStreak = 0
            nerve -= 1
            if nerve <= 0 {
                let zone = zoneForRound(round)
                round = zone.startRound
                while sequence.count > round { sequence.removeLast() }
                nerve = 3
                statusText = "The storm overwhelmed you! Back to \(zone.name)'s start."
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    guard myGeneration == generation else { return }
                    startRound(growSequence: false)
                }
            } else {
                statusText = "Missed it! \(nerve) nerve left - try this round again."
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    guard myGeneration == generation else { return }
                    startRound(growSequence: false)
                }
            }
        }
    }

    private func saveBest() {
        UserDefaults.standard.set(bestRound, forKey: bestKey)
    }

    private func finishChase() {
        generation += 1 // cancel any pending callbacks
        highlightedQuadrant = nil
        finished = true
        confetti.start()
    }

    private func restartChase() {
        finished = false
        round = 1
        nerve = 3
        perfectStreak = 0
        sequence.removeAll()
        startRound(growSequence: true)
    }
}
