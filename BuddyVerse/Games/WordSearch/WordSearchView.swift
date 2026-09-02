import SwiftUI

/// Mirrors WordSearchActivity + WordSearchGridLayout.kt: drag your finger
/// across the letter grid to select the hidden word. Bigger grids for higher
/// difficulties mean more distractor letters surrounding the word (the word
/// itself is always the same length either way), which is what makes it
/// harder to spot.
struct WordSearchView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    private struct GridCell: Equatable {
        let row: Int
        let col: Int
    }

    private let words = ["BUDDY", "GAMES", "FUNNY", "HAPPY", "VERSE"]
    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private let boardSide: CGFloat = 320

    @State private var gridSize = 6
    @State private var currentWord = ""
    @State private var letters: [[String]] = []
    // The exact (row, col) cells the target word was placed into, left to
    // right - checkWord() requires the player's selection to match this set
    // exactly, not just spell out the same letters.
    @State private var wordCells: [GridCell] = []
    @State private var selectedCells: [GridCell] = []
    @State private var toastMessage: String?
    @State private var showFeedback = false
    @State private var showReport = false

    private var difficulty: String { selection.difficulty ?? "EASY" }

    var body: some View {
        VStack(spacing: 10) {
            Text("Word Search")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Text("Find: \(currentWord)")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: 0xFFEB3B))

            if let toastMessage {
                Text(toastMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .transition(.opacity)
            }

            wordGrid
                .padding(.vertical, 10)

            // btnResetWordSearch: match_parent, 60dp, bg white, text #673AB7 bold
            Button("New Puzzle") { setupNewPuzzle() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: 0x673AB7))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

            // btnBackWordSearch: wrap_content, bg #AADDDDDD, text #333333
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
        .background(Color(hex: 0x673AB7).ignoresSafeArea())
        .confettiOverlay(confetti)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            gridSize = gridSizeForDifficulty()
            if letters.isEmpty { setupNewPuzzle() }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "WORDSEARCH") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "WORDSEARCH") }
    }

    private func gridSizeForDifficulty() -> Int {
        switch difficulty {
        case "HARD": return 8
        case "MEDIUM": return 6
        default: return 5 // EASY (and default)
        }
    }

    private var wordGrid: some View {
        let cellSize = boardSide / CGFloat(max(gridSize, 1))
        return ZStack(alignment: .topLeading) {
            ForEach(0..<gridSize, id: \.self) { r in
                ForEach(0..<gridSize, id: \.self) { c in
                    let cell = GridCell(row: r, col: c)
                    Text(letters.indices.contains(r) && letters[r].indices.contains(c) ? letters[r][c] : "")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: cellSize, height: cellSize)
                        .foregroundColor(selectedCells.contains(cell) ? .black : .white)
                        .background(selectedCells.contains(cell) ? Color(hex: 0xFFFF00) : Color.clear)
                        .position(x: CGFloat(c) * cellSize + cellSize / 2, y: CGFloat(r) * cellSize + cellSize / 2)
                }
            }
        }
        .frame(width: boardSide, height: boardSide)
        .background(Color.white.opacity(0.27))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in handleTouch(at: value.location, cellSize: cellSize) }
                .onEnded { _ in checkWord() }
        )
    }

    private func handleTouch(at point: CGPoint, cellSize: CGFloat) {
        guard cellSize > 0 else { return }
        let col = Int(point.x / cellSize)
        let row = Int(point.y / cellSize)
        guard row >= 0, row < gridSize, col >= 0, col < gridSize else { return }
        let cell = GridCell(row: row, col: col)
        if !selectedCells.contains(cell) {
            selectedCells.append(cell)
        }
    }

    private func setupNewPuzzle() {
        gridSize = gridSizeForDifficulty()
        selectedCells = []
        currentWord = words.randomElement() ?? "BUDDY"
        let wordLetters = Array(currentWord)

        // Simple horizontal placement logic for the target word.
        let row = Int.random(in: 0..<gridSize)
        var placedWordCells: [GridCell] = []
        var grid = Array(repeating: Array(repeating: "", count: gridSize), count: gridSize)

        for i in 0..<gridSize {
            for j in 0..<gridSize {
                if i == row && j < wordLetters.count {
                    placedWordCells.append(GridCell(row: i, col: j))
                    grid[i][j] = String(wordLetters[j])
                } else {
                    grid[i][j] = String(alphabet.randomElement() ?? "A")
                }
            }
        }

        letters = grid
        wordCells = placedWordCells
    }

    private func checkWord() {
        // Require the selected cells to be exactly the cells the word was
        // placed into (walked forward or backward) - not just letters that
        // happen to spell it out - so dragging across scattered, unrelated
        // cells can't win just because the letters lined up by chance.
        if selectedCells == wordCells || selectedCells == Array(wordCells.reversed()) {
            showToast("FOUND IT! Great job!")
            confetti.start()
            setupNewPuzzle()
        } else {
            if !selectedCells.isEmpty {
                showToast("Try again!")
            }
            selectedCells = []
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
    WordSearchView(selection: GameSelection(gameType: "WORDSEARCH", difficulty: "EASY"))
        .environmentObject(Router())
}
