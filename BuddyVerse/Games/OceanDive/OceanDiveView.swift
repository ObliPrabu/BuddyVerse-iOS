import SwiftUI

/// Mirrors OceanDiveActivity: tap the same button repeatedly to dive deeper.
/// Each tap costs one bubble (life) and randomly increases depth; running out
/// of bubbles shows a summary message and resets the round. No bot, no
/// nearby mode, no movement - the whole interaction is "tap the fixed
/// button, watch two counters."
struct OceanDiveView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    @State private var bubbles: Int
    @State private var depth = 0
    @State private var currentCreature = creatures.randomElement()!
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    private static let creatures = ["🐙", "🐡", "🐬", "🐳", "🦈"]

    // Fewer starting bubbles means fewer dives before you run out, so HARD
    // ends the round (and caps how deep you can get) much sooner.
    private let startingBubbles: Int

    init(selection: GameSelection) {
        self.selection = selection
        let starting: Int
        switch selection.difficulty {
        case "HARD": starting = 7
        case "MEDIUM": starting = 10
        default: starting = 14 // EASY (and default)
        }
        startingBubbles = starting
        _bubbles = State(initialValue: starting)
    }

    private var livesText: String {
        depth == 0 && bubbles == startingBubbles
            ? "Bubbles Left: \(bubbles)"
            : "Bubbles Left: \(bubbles) | Depth: \(depth)m"
    }

    var body: some View {
        ZStack {
            Color(hex: 0x0288D1).ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Ocean Dive")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                Text(livesText)
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: 0xB2EBF2))
                    .padding(.bottom, 40)

                Button {
                    dive()
                } label: {
                    Text(currentCreature)
                        .font(.system(size: 80))
                        .frame(width: 150, height: 150)
                        .background(Circle().fill(.white))
                }
                .padding(.bottom, 40)

                Text("Tap to dive deeper!\nDon't let the bubbles run out!")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 50)

                Button("Back to Menu") { router.pop() }
                    // Android's backgroundTint is #AADDDDDD - alpha 0xAA (~0.667), not fully opaque.
                    .buttonStyle(LegacyBorderedButtonStyle(tint: Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)))
                    .foregroundColor(Color(hex: 0x333333))
            }
            .padding(20)

            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.75)))
                        .foregroundColor(.white)
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
    }

    private func dive() {
        // Random depth increase between 1 and 20 meters.
        let depthIncrease = Int.random(in: 1...20)
        depth += depthIncrease
        bubbles -= 1
        currentCreature = Self.creatures.randomElement()!

        if bubbles <= 0 {
            showToast("Out of bubbles! You reached \(depth)m deep!")
            bubbles = startingBubbles
            depth = 0
        }
    }

    // Android's Toast can be silently dropped if several fire in quick
    // succession (see ISSUE-50 in the Android CLAUDE.md); this transient
    // banner is a straightforward SwiftUI equivalent that doesn't have that
    // failure mode, but keeping it as a self-dismissing overlay (rather than
    // a persistent label) matches the original's "flash a message" feel.
    private func showToast(_ text: String) {
        toastWorkItem?.cancel()
        toastMessage = text
        let workItem = DispatchWorkItem { toastMessage = nil }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }
}
