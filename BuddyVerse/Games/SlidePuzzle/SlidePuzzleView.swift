import SwiftUI

/// Mirrors SlidePuzzleActivity: an 8-tile sliding puzzle. Shuffles by walking
/// the empty tile backwards a number of random legal moves from the solved
/// state (rather than a pure random shuffle), which guarantees every
/// resulting board is solvable for free - no separate parity check needed -
/// and makes DIFFICULTY actually matter: fewer moves leaves the board closer
/// to solved (EASY), more moves scrambles it much further from solved (HARD).
struct SlidePuzzleView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    // 0 represents the empty tile, same convention as Android.
    @State private var tiles: [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 0]
    @State private var toastMessage: String?
    @State private var showFeedback = false
    @State private var showReport = false

    private var difficulty: String { selection.difficulty ?? "EASY" }
    private let solved = [1, 2, 3, 4, 5, 6, 7, 8, 0]

    var body: some View {
        VStack(spacing: 10) {
            Text("Slide Puzzle")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Text("Order the numbers 1-8")
                .font(.system(size: 18))
                .foregroundColor(Color(hex: 0xFFEB3B))

            if let toastMessage {
                Text(toastMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .transition(.opacity)
            }

            puzzleGrid
                .padding(.vertical, 20)

            // btnResetSlide: match_parent, 60dp, bg white, text #795548 bold
            Button("SHUFFLE") { shuffleBoard() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: 0x795548))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

            // btnBackSlide: wrap_content, bg #AADDDDDD, text #333333
            HStack(spacing: 10) {
                Button("Back") { router.pop() }
                Button("Home") { router.popToRoot() }
            }
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0x333333))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button("Feedback") { showFeedback = true }
                Button("Report") { showReport = true }
            }
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
        .background(Color(hex: 0x795548).ignoresSafeArea())
        .confettiOverlay(confetti)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { shuffleBoard() }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "SLIDE") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "SLIDE") }
    }

    private var puzzleGrid: some View {
        VStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { col in
                        tileButton(index: row * 3 + col)
                    }
                }
            }
        }
        .padding(5)
        .background(Color.white.opacity(0x44 / 255.0))
    }

    private func tileButton(index: Int) -> some View {
        let value = tiles[index]
        return Button {
            onTileClicked(index)
        } label: {
            Text(value == 0 ? "" : "\(value)")
                .font(.system(size: 24))
                .frame(width: 90, height: 90)
                .foregroundColor(Color(hex: 0x795548))
                .background(value == 0 ? Color.clear : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(value == 0)
    }

    private func onTileClicked(_ index: Int) {
        guard let emptyIndex = tiles.firstIndex(of: 0) else { return }

        // Check if the clicked tile is adjacent to the empty one.
        let isAdjacent: Bool
        switch index {
        case emptyIndex - 1: isAdjacent = index % 3 != 2 // Left
        case emptyIndex + 1: isAdjacent = index % 3 != 0 // Right
        case emptyIndex - 3: isAdjacent = true // Up
        case emptyIndex + 3: isAdjacent = true // Down
        default: isAdjacent = false
        }

        if isAdjacent {
            tiles[emptyIndex] = tiles[index]
            tiles[index] = 0
            checkWin()
        }
    }

    // Mirrors the adjacency rule used by onTileClicked, but the other way
    // round: given the empty tile's index, which indices could slide into it.
    private func adjacentIndices(_ index: Int) -> [Int] {
        var result: [Int] = []
        if index % 3 != 0 { result.append(index - 1) } // left neighbor exists
        if index % 3 != 2 { result.append(index + 1) } // right neighbor exists
        if index - 3 >= 0 { result.append(index - 3) } // up neighbor exists
        if index + 3 <= 8 { result.append(index + 3) } // down neighbor exists
        return result
    }

    private func shuffleBoard() {
        tiles = [1, 2, 3, 4, 5, 6, 7, 8, 0]
        let moveCount: Int
        switch difficulty {
        case "HARD": moveCount = 150
        case "MEDIUM": moveCount = 60
        default: moveCount = 20 // EASY (and default)
        }

        var emptyIndex = tiles.firstIndex(of: 0)!
        var previousEmptyIndex = -1
        for _ in 0..<moveCount {
            let candidates = adjacentIndices(emptyIndex).filter { $0 != previousEmptyIndex }
            guard let swapWith = candidates.randomElement() else { continue }
            tiles[emptyIndex] = tiles[swapWith]
            tiles[swapWith] = 0
            previousEmptyIndex = emptyIndex
            emptyIndex = swapWith
        }
    }

    private func checkWin() {
        if tiles == solved {
            showToast("PUZZLE SOLVED!")
            confetti.start()
        }
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
    SlidePuzzleView(selection: GameSelection(gameType: "SLIDE", difficulty: "EASY"))
        .environmentObject(Router())
}
