import XCTest

/// Swift twin of Android's SudokuGeneratorTest. Every puzzle is random, so
/// each test generates several and checks the rules that must hold for all of
/// them: a valid finished grid, a puzzle that agrees with it, exactly one
/// possible solution, and roughly the right number of clues per difficulty.
final class SudokuGeneratorTests: XCTestCase {

    private func isValidGroup(_ values: [Int]) -> Bool { values.sorted() == Array(1...9) }

    private func assertValidSolvedGrid(_ grid: [[Int]], file: StaticString = #filePath, line: UInt = #line) {
        for r in 0..<9 { XCTAssertTrue(isValidGroup(grid[r]), "row \(r)", file: file, line: line) }
        for c in 0..<9 { XCTAssertTrue(isValidGroup((0..<9).map { grid[$0][c] }), "column \(c)", file: file, line: line) }
        for box in 0..<9 {
            let br = (box / 3) * 3
            let bc = (box % 3) * 3
            let cells = (0..<9).map { grid[br + $0 / 3][bc + $0 % 3] }
            XCTAssertTrue(isValidGroup(cells), "box \(box)", file: file, line: line)
        }
    }

    private func clueCount(_ board: [[Int]]) -> Int { board.reduce(0) { $0 + $1.filter { $0 != 0 }.count } }

    // An independent solution counter, so the test does not just trust the generator's own.
    private func countSolutions(_ grid: inout [[Int]], limit: Int) -> Int {
        var pos = 0
        while pos < 81 && grid[pos / 9][pos % 9] != 0 { pos += 1 }
        if pos == 81 { return 1 }
        let r = pos / 9
        let c = pos % 9
        var count = 0
        for n in 1...9 {
            var clash = false
            for i in 0..<9 where grid[r][i] == n || grid[i][c] == n { clash = true }
            for dr in 0..<3 {
                for dc in 0..<3 where grid[(r / 3) * 3 + dr][(c / 3) * 3 + dc] == n { clash = true }
            }
            if clash { continue }
            grid[r][c] = n
            count += countSolutions(&grid, limit: limit)
            grid[r][c] = 0
            if count >= limit { break }
        }
        return count
    }

    func testSolutionIsAValidFinishedGrid() {
        for _ in 0..<5 { assertValidSolvedGrid(SudokuGenerator.generate(difficulty: "EASY").solution) }
    }

    func testPuzzleOnlyContainsNumbersFromItsSolution() {
        for level in ["EASY", "MEDIUM", "HARD"] {
            let p = SudokuGenerator.generate(difficulty: level)
            for r in 0..<9 {
                for c in 0..<9 {
                    let v = p.board[r][c]
                    XCTAssertTrue(v == 0 || v == p.solution[r][c], "\(level) cell \(r),\(c)")
                }
            }
        }
    }

    func testEveryDifficultyHasExactlyOneSolution() {
        for level in ["EASY", "MEDIUM", "HARD"] {
            for _ in 0..<2 {
                var copy = SudokuGenerator.generate(difficulty: level).board
                XCTAssertEqual(countSolutions(&copy, limit: 2), 1, "\(level) should have exactly one solution")
            }
        }
    }

    func testCluesMatchTheDifficulty() {
        // The generator stops at the target, or earlier if no more clues can go without
        // making the puzzle ambiguous, so the count is at least the target.
        for (level, target) in [("EASY", 42), ("MEDIUM", 32), ("HARD", 24)] {
            let clues = clueCount(SudokuGenerator.generate(difficulty: level).board)
            XCTAssertGreaterThanOrEqual(clues, target, level)
            XCTAssertLessThan(clues, 81, "\(level) should be a puzzle, not a finished grid")
        }
    }

    func testHarderLevelsLeaveFewerCluesOnAverage() {
        func average(_ level: String) -> Double {
            let counts = (1...4).map { _ in clueCount(SudokuGenerator.generate(difficulty: level).board) }
            return Double(counts.reduce(0, +)) / Double(counts.count)
        }
        XCTAssertGreaterThan(average("EASY"), average("HARD"))
    }

    func testUnknownDifficultyBehavesLikeEasy() {
        XCTAssertGreaterThanOrEqual(clueCount(SudokuGenerator.generate(difficulty: "NONSENSE").board), 42)
    }

    func testHardPuzzlesGenerateInReasonableTime() {
        // iOS ISSUE-91 worried HARD generation could be slow on some seeds.
        let start = Date()
        for _ in 0..<5 { _ = SudokuGenerator.generate(difficulty: "HARD") }
        let seconds = Date().timeIntervalSince(start)
        XCTAssertLessThan(seconds, 30, "5 HARD puzzles took \(seconds) s")
    }
}
