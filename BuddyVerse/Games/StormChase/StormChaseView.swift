import SwiftUI

/// Mirrors StormChaseActivity: a Simon-says memory game. The storm "strikes"
/// a growing sequence across a 2x2 grid of quadrants, then you tap them back
/// in the same order. A full correct sequence grows it by one for the next
/// round; one wrong tap and the storm gets you, resetting back to round 1.
/// No bot, no nearby mode.
struct StormChaseView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    @State private var sequence: [Int] = []
    @State private var inputIndex = 0
    @State private var round = 1
    @State private var acceptingInput = false
    @State private var statusText = "Watch the storm's path..."
    @State private var highlightedQuadrant: Int?
    // Bumped every time a fresh round starts (or the view disappears), so
    // stale delayed callbacks from a superseded sequence can recognize
    // they're outdated and no-op instead of animating/advancing state that
    // no longer applies - the Swift equivalent of Android's
    // handler.removeCallbacksAndMessages(null) in onDestroy.
    @State private var generation = 0
    @State private var showFeedback = false
    @State private var showReport = false

    private static let quadrantSymbols = ["⚡", "🌩️", "⛈️", "🌧️"]
    private static let quadrantColor = Color(hex: 0x607D8B)
    private static let highlightColor = Color(hex: 0xFFEB3B)

    // How fast each step of the sequence flashes - shorter flashes mean
    // less time to notice and remember each step, which is what makes HARD
    // harder here.
    private var flashDuration: TimeInterval {
        switch selection.difficulty {
        case "HARD": return 0.3
        case "MEDIUM": return 0.42
        default: return 0.55 // EASY (and default)
        }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x37474F).ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Storm Chase")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                Text(statusText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFEB3B))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("Round: \(round)")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.bottom, 40)

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
                .padding(.bottom, 50)

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
            }
            .padding(20)
        }
        .onAppear { startRound() }
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

    private func startRound() {
        generation += 1
        let myGeneration = generation
        acceptingInput = false
        inputIndex = 0
        sequence.append(Int.random(in: 0..<4))
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
        guard acceptingInput else { return }

        if index == sequence[inputIndex] {
            inputIndex += 1
            if inputIndex == sequence.count {
                acceptingInput = false
                statusText = "Nice! Next round..."
                round += 1
                let myGeneration = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    guard myGeneration == generation else { return }
                    startRound()
                }
            }
        } else {
            acceptingInput = false
            let survivedRounds = round
            statusText = "The storm got you! Survived \(survivedRounds) round\(survivedRounds == 1 ? "" : "s")."
            round = 1
            sequence.removeAll()
            let myGeneration = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                guard myGeneration == generation else { return }
                startRound()
            }
        }
    }
}
