import SwiftUI

/// Mirrors MazeActivity + MazeView.kt: a recursive-backtracker-generated
/// maze, drawn on a Canvas, driven by swipes, arrow buttons, or (on an
/// external keyboard) arrow keys. Bigger grids for higher difficulties make
/// for a genuinely harder maze, not just the same layout every time.
struct MazeGameView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    private enum Direction { case up, down, left, right }

    private struct MazeCell {
        var topWall = true
        var leftWall = true
        var bottomWall = true
        var rightWall = true
        var visited = false
    }

    @State private var cols = 12
    @State private var rows = 18
    @State private var cells: [[MazeCell]] = []
    @State private var playerCol = 0
    @State private var playerRow = 0
    @State private var toastMessage: String?
    @State private var showFeedback = false
    @State private var showReport = false

    private var baseMazeCanvas: some View {
        mazeCanvas
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(swipeGesture)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("The Amazing Maze")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.bold())
                    .foregroundColor(.yellow)
                    .transition(.opacity)
            }

            // Hardware-keyboard arrow-key support needs `@FocusState`/
            // `.onKeyPress` (iOS 15/17+ respectively) - a stored property of
            // an iOS-15+-only type can't just be guarded at the use site the
            // way a modifier call can (the type has to exist in every build
            // of this struct), so it lives in its own iOS-17-gated helper
            // view instead of directly on MazeGameView. Swipe gesture + the
            // on-screen arrowControls below give full maze control on every
            // iOS version regardless, so this is a pure bonus on newer devices.
            if #available(iOS 17, *) {
                KeyboardControlledMazeCanvas(
                    moveUp: { movePlayer(.up) },
                    moveDown: { movePlayer(.down) },
                    moveLeft: { movePlayer(.left) },
                    moveRight: { movePlayer(.right) }
                ) { baseMazeCanvas }
            } else {
                baseMazeCanvas
            }

            arrowControls

            HStack(spacing: 10) {
                Button("Back to Menu") { router.pop() }
                Button("Home") { router.popToRoot() }
            }
            .buttonStyle(LegacyProminentButtonStyle(tint: .white))
            .foregroundColor(Color(hex: 0x009688))
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Button("Feedback") { showFeedback = true }
                Button("Report") { showReport = true }
            }
            .buttonStyle(LegacyProminentButtonStyle(tint: .white))
            .foregroundColor(Color(hex: 0x009688))
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(hex: 0x009688).ignoresSafeArea())
        .confettiOverlay(confetti)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if cells.isEmpty {
                configureDifficulty(selection.difficulty)
            }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "MAZE") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "MAZE") }
    }

    // MARK: - Controls

    private var arrowControls: some View {
        VStack(spacing: 6) {
            arrowButton("↑") { movePlayer(.up) }
            HStack(spacing: 6) {
                arrowButton("←") { movePlayer(.left) }
                arrowButton("↓") { movePlayer(.down) }
                arrowButton("→") { movePlayer(.right) }
            }
        }
    }

    private func arrowButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 24))
                .foregroundColor(Color(hex: 0x009688))
                .frame(width: 60, height: 60)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let diffX = value.translation.width
                let diffY = value.translation.height
                if abs(diffX) > abs(diffY) {
                    if abs(diffX) > 50 {
                        movePlayer(diffX > 0 ? .right : .left)
                    }
                } else {
                    if abs(diffY) > 50 {
                        movePlayer(diffY > 0 ? .down : .up)
                    }
                }
            }
    }

    // MARK: - Drawing

    // `Canvas` needs iOS 15 - `Path` itself has conformed to `Shape` (so it
    // can be `.stroke()`d/`.fill()`d directly) since iOS 13, which is all
    // this drawing actually needs. The margin (`hMargin`/`vMargin`, real
    // Canvas's `context.translateBy`) is just baked directly into every
    // point instead of applied as a transform.
    private var mazeCanvas: some View {
        GeometryReader { geo in
            ZStack {
                if cols > 0, rows > 0, !cells.isEmpty {
                    let width = geo.size.width
                    let height = geo.size.height
                    let cellSize: CGFloat = (width / height) < (CGFloat(cols) / CGFloat(rows))
                        ? width / CGFloat(cols + 1)
                        : height / CGFloat(rows + 1)
                    let hMargin = (width - CGFloat(cols) * cellSize) / 2
                    let vMargin = (height - CGFloat(rows) * cellSize) / 2
                    let margin = cellSize / 10

                    wallPath(cellSize: cellSize, hMargin: hMargin, vMargin: vMargin)
                        .stroke(Color.white, lineWidth: 2)

                    // Android Paint colors: Color.YELLOW (#FFFF00), Color.GREEN (#00FF00) - pure values, not SwiftUI's system yellow/green.
                    Path(CGRect(
                        x: CGFloat(playerCol) * cellSize + margin + hMargin,
                        y: CGFloat(playerRow) * cellSize + margin + vMargin,
                        width: cellSize - 2 * margin,
                        height: cellSize - 2 * margin
                    )).fill(Color(hex: 0xFFFF00))

                    Path(CGRect(
                        x: CGFloat(cols - 1) * cellSize + margin + hMargin,
                        y: CGFloat(rows - 1) * cellSize + margin + vMargin,
                        width: cellSize - 2 * margin,
                        height: cellSize - 2 * margin
                    )).fill(Color(hex: 0x00FF00))
                }
            }
        }
        .background(Color(hex: 0x009688))
    }

    private func wallPath(cellSize: CGFloat, hMargin: CGFloat, vMargin: CGFloat) -> Path {
        var wallPath = Path()
        for c in 0..<cols {
            for r in 0..<rows {
                let cell = cells[c][r]
                let x0 = CGFloat(c) * cellSize + hMargin
                let y0 = CGFloat(r) * cellSize + vMargin
                let x1 = CGFloat(c + 1) * cellSize + hMargin
                let y1 = CGFloat(r + 1) * cellSize + vMargin
                if cell.topWall {
                    wallPath.move(to: CGPoint(x: x0, y: y0))
                    wallPath.addLine(to: CGPoint(x: x1, y: y0))
                }
                if cell.leftWall {
                    wallPath.move(to: CGPoint(x: x0, y: y0))
                    wallPath.addLine(to: CGPoint(x: x0, y: y1))
                }
                if cell.bottomWall {
                    wallPath.move(to: CGPoint(x: x0, y: y1))
                    wallPath.addLine(to: CGPoint(x: x1, y: y1))
                }
                if cell.rightWall {
                    wallPath.move(to: CGPoint(x: x1, y: y0))
                    wallPath.addLine(to: CGPoint(x: x1, y: y1))
                }
            }
        }
        return wallPath
    }

    // MARK: - Maze generation (recursive backtracker)

    /// Resizes the maze grid based on difficulty and builds a brand new one.
    private func configureDifficulty(_ difficulty: String?) {
        switch difficulty ?? "EASY" {
        case "HARD": cols = 24; rows = 34
        case "MEDIUM": cols = 17; rows = 25
        default: cols = 12; rows = 18 // EASY (and default)
        }
        cells = Array(repeating: Array(repeating: MazeCell(), count: rows), count: cols)
        playerCol = 0
        playerRow = 0
        generateMaze()
    }

    private func generateMaze() {
        var stack: [(col: Int, row: Int)] = []
        var current: (col: Int, row: Int) = (0, 0)
        cells[0][0].visited = true

        while true {
            if let next = getNeighbor(current) {
                removeWall(current, next)
                stack.append(current)
                current = next
                cells[current.col][current.row].visited = true
            } else if !stack.isEmpty {
                current = stack.removeLast()
            } else {
                break
            }
        }
    }

    private func getNeighbor(_ cell: (col: Int, row: Int)) -> (col: Int, row: Int)? {
        var neighbors: [(col: Int, row: Int)] = []
        if cell.col > 0 && !cells[cell.col - 1][cell.row].visited { neighbors.append((cell.col - 1, cell.row)) }
        if cell.col < cols - 1 && !cells[cell.col + 1][cell.row].visited { neighbors.append((cell.col + 1, cell.row)) }
        if cell.row > 0 && !cells[cell.col][cell.row - 1].visited { neighbors.append((cell.col, cell.row - 1)) }
        if cell.row < rows - 1 && !cells[cell.col][cell.row + 1].visited { neighbors.append((cell.col, cell.row + 1)) }
        return neighbors.randomElement()
    }

    private func removeWall(_ current: (col: Int, row: Int), _ next: (col: Int, row: Int)) {
        if current.col == next.col && current.row == next.row + 1 {
            cells[current.col][current.row].topWall = false
            cells[next.col][next.row].bottomWall = false
        }
        if current.col == next.col && current.row == next.row - 1 {
            cells[current.col][current.row].bottomWall = false
            cells[next.col][next.row].topWall = false
        }
        if current.col == next.col + 1 && current.row == next.row {
            cells[current.col][current.row].leftWall = false
            cells[next.col][next.row].rightWall = false
        }
        if current.col == next.col - 1 && current.row == next.row {
            cells[current.col][current.row].rightWall = false
            cells[next.col][next.row].leftWall = false
        }
    }

    // MARK: - Movement / win

    private func movePlayer(_ direction: Direction) {
        guard !cells.isEmpty else { return }
        let cell = cells[playerCol][playerRow]
        switch direction {
        case .up: if playerRow > 0 && !cell.topWall { playerRow -= 1 }
        case .down: if playerRow < rows - 1 && !cell.bottomWall { playerRow += 1 }
        case .left: if playerCol > 0 && !cell.leftWall { playerCol -= 1 }
        case .right: if playerCol < cols - 1 && !cell.rightWall { playerCol += 1 }
        }
        checkWin()
    }

    private func checkWin() {
        if playerCol == cols - 1 && playerRow == rows - 1 {
            showToast("CONGRATULATIONS! You escaped the maze!")
            confetti.start()
            resetGame()
        }
    }

    private func resetGame() {
        for c in 0..<cols {
            for r in 0..<rows {
                cells[c][r] = MazeCell()
            }
        }
        generateMaze()
        playerCol = 0
        playerRow = 0
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

/// Adds hardware-keyboard arrow-key control on top of any content - split
/// out from MazeGameView because it needs `@FocusState` (iOS 15+) as a
/// stored property, which (unlike a modifier call) can't be conditionally
/// present on a single struct depending on OS version.
@available(iOS 17, *)
private struct KeyboardControlledMazeCanvas<Content: View>: View {
    let moveUp: () -> Void
    let moveDown: () -> Void
    let moveLeft: () -> Void
    let moveRight: () -> Void
    @ViewBuilder let content: () -> Content

    @FocusState private var isFocused: Bool

    var body: some View {
        content()
            .focusable()
            .focused($isFocused)
            .onKeyPress(.upArrow) { moveUp(); return .handled }
            .onKeyPress(.downArrow) { moveDown(); return .handled }
            .onKeyPress(.leftArrow) { moveLeft(); return .handled }
            .onKeyPress(.rightArrow) { moveRight(); return .handled }
            .onAppear { isFocused = true }
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
    MazeGameView(selection: GameSelection(gameType: "MAZE", difficulty: "EASY"))
        .environmentObject(Router())
}
