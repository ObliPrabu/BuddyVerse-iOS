import SwiftUI

/// Mirrors SudokuActivity: a 9x9 board filled in by tapping a blank cell and
/// picking a number, backed by SudokuGenerator for real, uniquely-solvable
/// puzzles. Blocks are shaded to make the 3x3 boxes easy to read, given
/// clues render bold black, player-entered numbers render blue, and revealed
/// answer cells render bold orange - matching the Android color scheme.
struct SudokuView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    @State private var board: [[Int]] = SudokuView.emptyBoard()
    @State private var initialBoard: [[Int]] = SudokuView.emptyBoard()
    @State private var solutionBoard: [[Int]] = SudokuView.emptyBoard()
    @State private var isBusy = false
    @State private var answerRevealed = false
    // Bumped every time a freshly-generated puzzle is applied - mirrors
    // puzzleGeneration on Android. Lets a still-open number picker notice its
    // puzzle was replaced underneath it (a background regeneration finishing
    // while the picker was open) and ignore its own stale selection instead
    // of writing into what may now be a "given" clue cell.
    @State private var puzzleGeneration = 0
    @State private var toastMessage: String?

    @State private var pickerCell: (row: Int, col: Int)?
    @State private var pickerGeneration = 0

    private var difficulty: String { selection.difficulty ?? "EASY" }

    static func emptyBoard() -> [[Int]] { Array(repeating: Array(repeating: 0, count: 9), count: 9) }

    var body: some View {
        VStack(spacing: 16) {
            Text("Sudoku")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 8)

            sudokuGrid
                .disabled(isBusy || answerRevealed)

            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.bold())
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                // btnCheckSudoku: bg #4CAF50, no textColor override (white default)
                Button("Check") { checkBoard() }
                    .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0x4CAF50)))
                    .foregroundColor(.white)
                // btnNewSudoku: bg white, text #3F51B5
                Button("New") { startNewGame() }
                    .buttonStyle(LegacyProminentButtonStyle(tint: .white))
                    .foregroundColor(Color(hex: 0x3F51B5))
                // btnShowAnswer: bg #FF9800, text white
                Button("Answer") { showAnswer() }
                    .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0xFF9800)))
                    .foregroundColor(.white)
            }
            .disabled(isBusy)

            // btnBackSudoku: bg #AADDDDDD, text #333333
            Button("Back") { router.pop() }
                .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0)))
                .foregroundColor(Color(hex: 0x333333))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x3F51B5).ignoresSafeArea())
        .confettiOverlay(confetti)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if puzzleGeneration == 0 { startNewGame() }
        }
        // `.confirmationDialog` needs iOS 15 - this is the ActionSheet
        // (iOS 13+) equivalent.
        .actionSheet(isPresented: pickerPresented) {
            ActionSheet(
                title: Text("Pick a number"),
                buttons: (1...9).map { n in
                    .default(Text("\(n)")) { applyPick(n) }
                } + [
                    .default(Text("Clear")) { applyPick(0) },
                    .cancel(Text("Cancel")) { pickerCell = nil }
                ]
            )
        }
    }

    private var pickerPresented: Binding<Bool> {
        Binding(get: { pickerCell != nil }, set: { if !$0 { pickerCell = nil } })
    }

    private var sudokuGrid: some View {
        VStack(spacing: 1) {
            ForEach(0..<9, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<9, id: \.self) { col in
                        cellButton(row: row, col: col)
                    }
                }
            }
        }
        .padding(2)
        .background(Color.black)
    }

    private func cellButton(row: Int, col: Int) -> some View {
        let value = board[row][col]
        let isGiven = initialBoard[row][col] != 0
        let blockShade = ((row / 3) + (col / 3)) % 2 == 0
        return Button {
            if !isGiven && !answerRevealed { openPicker(row: row, col: col) }
        } label: {
            Text(value == 0 ? "" : "\(value)")
                .font(.system(size: 14, weight: (isGiven || (answerRevealed && !isGiven)) ? .bold : .regular))
                .foregroundColor(cellTextColor(row: row, col: col))
                .frame(width: 34, height: 34)
                .background(blockShade ? Color(hex: 0xEEEEEE) : Color(hex: 0xDDDDDD))
        }
        .buttonStyle(.plain)
    }

    private func cellTextColor(row: Int, col: Int) -> Color {
        if answerRevealed && initialBoard[row][col] == 0 { return Color(hex: 0xFF9800) }
        if initialBoard[row][col] != 0 { return .black }
        return .blue
    }

    private func openPicker(row: Int, col: Int) {
        pickerGeneration = puzzleGeneration
        pickerCell = (row, col)
    }

    private func applyPick(_ value: Int) {
        guard let cell = pickerCell else { return }
        pickerCell = nil
        // A background regeneration may have swapped in a new puzzle while
        // this picker was open - ignore the stale pick rather than writing
        // into what may now be a "given" clue cell.
        guard pickerGeneration == puzzleGeneration else { return }
        board[cell.row][cell.col] = value
    }

    private func startNewGame() {
        guard !isBusy else { return }
        isBusy = true
        answerRevealed = false
        showToast("Building your puzzle...")

        // Puzzle generation (plus the uniqueness check) does real work, so it
        // runs off the main thread and only touches state once it's ready -
        // mirrors the background Thread{} + runOnUiThread{} on Android.
        let requestedDifficulty = difficulty
        DispatchQueue.global(qos: .userInitiated).async {
            let puzzle = SudokuGenerator.generate(difficulty: requestedDifficulty)
            DispatchQueue.main.async {
                applyPuzzle(puzzle)
                isBusy = false
            }
        }
    }

    private func applyPuzzle(_ puzzle: SudokuGenerator.Puzzle) {
        puzzleGeneration += 1
        solutionBoard = puzzle.solution
        board = puzzle.board
        initialBoard = puzzle.board
    }

    private func showAnswer() {
        answerRevealed = true
        board = solutionBoard
        showToast("Here's the answer! Tap New for a fresh puzzle.")
    }

    private func checkBoard() {
        let isComplete = board.allSatisfy { row in row.allSatisfy { $0 != 0 } }
        guard isComplete else {
            showToast("The board is not complete yet!")
            return
        }
        if isBoardValid() {
            showToast("CONGRATULATIONS! You solved it!")
            confetti.start()
        } else {
            showToast("Something is wrong. Keep trying!")
        }
    }

    private func isBoardValid() -> Bool {
        for i in 0..<9 {
            var rowSet = Set<Int>()
            var colSet = Set<Int>()
            var boxSet = Set<Int>()
            for j in 0..<9 {
                if !rowSet.insert(board[i][j]).inserted { return false }
                if !colSet.insert(board[j][i]).inserted { return false }
                let rowIndex = 3 * (i / 3) + j / 3
                let colIndex = 3 * (i % 3) + j % 3
                if !boxSet.insert(board[rowIndex][colIndex]).inserted { return false }
            }
        }
        return true
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
    SudokuView(selection: GameSelection(gameType: "SUDOKU", difficulty: "EASY"))
        .environmentObject(Router())
}
