import Foundation

/// Mirrors SudokuGenerator.kt: builds real, guaranteed-solvable Sudoku
/// puzzles instead of using one fixed, hardcoded board every time.
///
/// How it works, in plain terms:
/// 1. Fill a completely solved 9x9 grid at random (this is the "answer").
/// 2. Erase numbers from it one at a time, but only if the puzzle still has
///    exactly ONE possible solution after erasing - otherwise put the number
///    back. This guarantees every puzzle we hand the player is actually
///    possible to solve, and has one correct answer (no guessing between
///    multiple valid solutions).
/// 3. Keep erasing until we've removed roughly the right number of clues for
///    the requested difficulty.
enum SudokuGenerator {

    struct Puzzle {
        let board: [[Int]]
        let solution: [[Int]]
    }

    /// Roughly how many of the 81 cells to leave filled in, per difficulty.
    private static func cluesToKeep(_ difficulty: String) -> Int {
        switch difficulty {
        case "HARD": return 24
        case "MEDIUM": return 32
        default: return 42 // EASY
        }
    }

    static func generate(difficulty: String) -> Puzzle {
        let solution = generateSolvedGrid()
        let puzzle = carve(solution: solution, targetClues: cluesToKeep(difficulty))
        return Puzzle(board: puzzle, solution: solution)
    }

    // --- Step 1: build a full, valid, randomly-shuffled solved grid ---

    private static func generateSolvedGrid() -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 9), count: 9)
        _ = fillCell(&grid, 0)
        return grid
    }

    @discardableResult
    private static func fillCell(_ grid: inout [[Int]], _ pos: Int) -> Bool {
        if pos == 81 { return true }
        let row = pos / 9
        let col = pos % 9
        let candidates = Array(1...9).shuffled()
        for num in candidates {
            if canPlace(grid, row, col, num) {
                grid[row][col] = num
                if fillCell(&grid, pos + 1) { return true }
                grid[row][col] = 0
            }
        }
        return false
    }

    private static func canPlace(_ grid: [[Int]], _ row: Int, _ col: Int, _ num: Int) -> Bool {
        for i in 0..<9 {
            if grid[row][i] == num { return false }
            if grid[i][col] == num { return false }
        }
        let boxRow = (row / 3) * 3
        let boxCol = (col / 3) * 3
        for r in 0..<3 {
            for c in 0..<3 {
                if grid[boxRow + r][boxCol + c] == num { return false }
            }
        }
        return true
    }

    // --- Step 2: carve holes into the solved grid, keeping the solution unique ---

    private static func carve(solution: [[Int]], targetClues: Int) -> [[Int]] {
        var puzzle = solution
        let positions = Array(0..<81).shuffled()
        var cluesLeft = 81

        for pos in positions {
            if cluesLeft <= targetClues { break }

            let row = pos / 9
            let col = pos % 9
            if puzzle[row][col] == 0 { continue }

            let backup = puzzle[row][col]
            puzzle[row][col] = 0

            let solutions = countSolutions(&puzzle, 0, 2)
            if solutions != 1 {
                // Removing this cell made it unsolvable or ambiguous - undo.
                puzzle[row][col] = backup
            } else {
                cluesLeft -= 1
            }
        }
        return puzzle
    }

    // Counts how many solutions exist, stopping early once it hits `limit`
    // (we only ever need to know if there's 0, 1, or "more than 1").
    private static func countSolutions(_ grid: inout [[Int]], _ startPos: Int, _ limit: Int) -> Int {
        var pos = startPos
        while pos < 81 && grid[pos / 9][pos % 9] != 0 { pos += 1 }
        if pos == 81 { return 1 }

        let row = pos / 9
        let col = pos % 9
        var count = 0
        for num in 1...9 {
            if canPlace(grid, row, col, num) {
                grid[row][col] = num
                count += countSolutions(&grid, pos + 1, limit)
                grid[row][col] = 0
                if count >= limit { break }
            }
        }
        return count
    }
}
