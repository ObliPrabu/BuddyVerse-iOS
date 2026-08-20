import SwiftUI

/// Mirrors MemorySequenceActivity: a Simon-says style memory game. Tapping
/// START plays back a growing sequence of flashing colored buttons; the
/// player repeats it back in order, one mistake resets the whole thing.
/// DIFFICULTY controls how fast the sequence flashes by (shorter gaps/flashes
/// give the player less time to register each step) - the sequence itself
/// grows the same way regardless of difficulty.
struct MemorySequenceView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    // Mirrors the android:backgroundTint values in activity_memory_sequence.xml.
    private let sequenceColors: [Color] = [
        Color(hex: 0xF44336), // red
        Color(hex: 0x2196F3), // blue
        Color(hex: 0x4CAF50), // green
        Color(hex: 0xFFEB3B)  // yellow
    ]

    @State private var sequence: [Int] = []
    @State private var userIndex = 0
    @State private var isPlayingSequence = false
    @State private var statusText = "Watch the sequence!"
    @State private var flashedIndex: Int?
    @State private var toastMessage: String?
    @State private var pendingWork: [DispatchWorkItem] = []

    private var difficulty: String { selection.difficulty ?? "EASY" }

    // Controls how fast the sequence flashes by - shorter gaps/flashes give
    // the player less time to register each step, which is what actually
    // makes HARD harder here (the sequence itself grows the same way either way).
    private var stepIntervalMs: Int {
        switch difficulty {
        case "HARD": return 450
        case "MEDIUM": return 650
        default: return 900 // EASY (and default)
        }
    }
    private var flashDurationMs: Int {
        switch difficulty {
        case "HARD": return 250
        case "MEDIUM": return 350
        default: return 500 // EASY (and default)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Memory Sequence")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Text(statusText)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: 0xFFEB3B))

            if let toastMessage {
                Text(toastMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            colorGrid
                .padding(.vertical, 20)

            // btnStartSequence: match_parent, 60dp, bg white, text #37474F bold
            Button("START") { if !isPlayingSequence { startGame() } }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: 0x37474F))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

            // btnBackSequence: wrap_content, bg #AADDDDDD, text #333333
            Button("Back") { router.pop() }
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0x333333))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x37474F).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { cancelPending() }
    }

    private var colorGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                colorButton(0)
                colorButton(1)
            }
            HStack(spacing: 10) {
                colorButton(2)
                colorButton(3)
            }
        }
    }

    private func colorButton(_ index: Int) -> some View {
        Button {
            if !isPlayingSequence { onButtonClicked(index) }
        } label: {
            Rectangle()
                .fill(flashedIndex == index ? Color.white : sequenceColors[index])
                .frame(width: 120, height: 120)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Game flow

    private func startGame() {
        // Clear any pending flash/next-step callbacks from a previous round
        // so they can't fire after this new game has already reset state.
        cancelPending()
        sequence = []
        addNewStep()
    }

    private func addNewStep() {
        sequence.append(Int.random(in: 0...3))
        playSequence()
    }

    private func playSequence() {
        isPlayingSequence = true
        userIndex = 0
        statusText = "Watch..."

        var delay = 500
        for index in sequence {
            schedule(after: delay) { flashButton(index) }
            delay += stepIntervalMs
        }

        schedule(after: delay) {
            isPlayingSequence = false
            statusText = "Your Turn!"
        }
    }

    private func flashButton(_ index: Int) {
        flashedIndex = index
        schedule(after: flashDurationMs) {
            flashedIndex = nil
        }
    }

    private func onButtonClicked(_ index: Int) {
        guard !sequence.isEmpty else { return }

        if index == sequence[userIndex] {
            userIndex += 1
            if userIndex == sequence.count {
                statusText = "Correct!"
                // Block input during the pause before the next round is
                // played, otherwise a tap here re-enters onButtonClicked with
                // userIndex out of range.
                isPlayingSequence = true
                schedule(after: 1000) { addNewStep() }
            }
        } else {
            showToast("Wrong sequence! Game Over. Score: \(sequence.count - 1)")
            sequence = []
            statusText = "Tap START to try again"
        }
    }

    // MARK: - Timer plumbing (mirrors Handler.postDelayed / removeCallbacksAndMessages)

    private func schedule(after ms: Int, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        pendingWork.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: item)
    }

    private func cancelPending() {
        pendingWork.forEach { $0.cancel() }
        pendingWork.removeAll()
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toastMessage == message {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#Preview {
    MemorySequenceView(selection: GameSelection(gameType: "SEQUENCE", difficulty: "EASY"))
        .environmentObject(Router())
}
