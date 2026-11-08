import Foundation

// Mirrors CheckersEngine.kt: the rules of American checkers (English draughts)
// and a small search-based bot, written from scratch with no library. Foundation
// only, so the logic tests run without a simulator.
//
// Board: squares 0...63, row = sq / 8 (row 0 is the top of the screen), col = sq % 8.
// Only the dark squares, where (row + col) is odd, are ever used. Red starts at
// the bottom (rows 5-7) and moves UP the screen; Black starts at the top (rows
// 0-2) and moves DOWN. Red moves first.
//
// Rules: men step one square diagonally forward; kings step one square
// diagonally in any direction (no flying kings); a jump over an enemy piece into
// the empty square behind it is COMPULSORY, and so is carrying on with further
// jumps with the same piece; a man that finishes a move on the far row is
// crowned, and a jump that crowns ends there; you lose when you have no piece
// that can move; 40 moves each (80 plies) without a capture or a man move is a
// draw, and so is a position that occurs a third time.

enum Checkers {
    static let empty = 0
    static let redMan = 1
    static let redKing = 2
    static let blackMan = -1
    static let blackKing = -2

    /// Plies (half-moves) without a capture or a man move before the game is drawn.
    static let drawPlies = 80

    static func isRed(_ p: Int) -> Bool { p > 0 }
    static func isKing(_ p: Int) -> Bool { p == redKing || p == blackKing }
    static func row(_ sq: Int) -> Int { sq / 8 }
    static func col(_ sq: Int) -> Int { sq % 8 }
    static func isDark(_ sq: Int) -> Bool { (row(sq) + col(sq)) % 2 == 1 }
    static func square(_ row: Int, _ col: Int) -> Int { row * 8 + col }
}

/// One whole move: the square the piece starts on followed by every square it
/// lands on. A plain step has two entries; a jump sequence has one landing
/// square per jumped piece. The pieces jumped over are the squares halfway
/// between neighbouring entries, so they never need to be stored.
struct CheckersMove: Equatable, Hashable {
    let path: [Int]

    var from: Int { path[0] }
    var to: Int { path[path.count - 1] }
    var isCapture: Bool { path.count >= 2 && abs(Checkers.row(path[0]) - Checkers.row(path[1])) == 2 }

    /// The squares of the pieces this move captures, in order.
    func captured() -> [Int] {
        guard isCapture else { return [] }
        return (0..<(path.count - 1)).map { (path[$0] + path[$0 + 1]) / 2 }
    }

    /// "12-17" style text, used on the wire and in tests.
    func toWire() -> String { path.map(String.init).joined(separator: "-") }

    /// Reads "12-17-26"; nil for anything malformed or off the board.
    static func fromWire(_ text: String) -> CheckersMove? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count < 2 || parts.count > 13 { return nil }
        var squares: [Int] = []
        for p in parts {
            guard let n = Int(p), (0...63).contains(n), Checkers.isDark(n) else { return nil }
            squares.append(n)
        }
        return CheckersMove(path: squares)
    }
}

struct CheckersPosition {
    var board: [Int]
    var redToMove: Bool
    /// Plies since the last capture or man move, for the draw rule.
    var quietPlies: Int

    init(board: [Int] = CheckersPosition.startBoard(), redToMove: Bool = true, quietPlies: Int = 0) {
        self.board = board
        self.redToMove = redToMove
        self.quietPlies = quietPlies
    }

    /// Identifies the position (pieces + side to move) for the repetition draw.
    func key() -> String { board.map(String.init).joined(separator: ",") + (redToMove ? "R" : "B") }

    static func startBoard() -> [Int] {
        var b = [Int](repeating: 0, count: 64)
        for sq in 0..<64 where Checkers.isDark(sq) {
            let r = Checkers.row(sq)
            if r <= 2 { b[sq] = Checkers.blackMan }
            if r >= 5 { b[sq] = Checkers.redMan }
        }
        return b
    }
}

enum CheckersResult { case ongoing, redWins, blackWins, draw }

enum CheckersRules {
    /// Directions a piece may step or jump in: (row change, column change).
    private static func directions(_ piece: Int) -> [(Int, Int)] {
        switch piece {
        case Checkers.redMan: return [(-1, -1), (-1, 1)]
        case Checkers.blackMan: return [(1, -1), (1, 1)]
        default: return [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        }
    }

    private static func onBoard(_ r: Int, _ c: Int) -> Bool { (0...7).contains(r) && (0...7).contains(c) }

    /// All full jump sequences for the piece on `from`.
    private static func jumpsFrom(_ board: [Int], _ from: Int) -> [[Int]] {
        let piece = board[from]
        var out: [[Int]] = []
        func walk(_ pos: Int, _ path: [Int], _ taken: Set<Int>, _ current: Int) {
            var extended = false
            for (dr, dc) in directions(current) {
                let mr = Checkers.row(pos) + dr
                let mc = Checkers.col(pos) + dc
                let lr = mr + dr
                let lc = mc + dc
                if !onBoard(lr, lc) { continue }
                let mid = Checkers.square(mr, mc)
                let land = Checkers.square(lr, lc)
                let victim = board[mid]
                if victim == 0 || Checkers.isRed(victim) == Checkers.isRed(piece) || taken.contains(mid) { continue }
                // The square the jumper started on counts as empty once it has left it.
                if board[land] != 0 && land != from { continue }
                extended = true
                let crowned = (current == Checkers.redMan && lr == 0) || (current == Checkers.blackMan && lr == 7)
                let next = path + [land]
                if crowned {
                    out.append(next)       // a jump that crowns a man ends the move
                } else {
                    walk(land, next, taken.union([mid]), current)
                }
            }
            if !extended && path.count > 1 { out.append(path) }
        }
        walk(from, [from], [], piece)
        return out
    }

    private static func stepsFrom(_ board: [Int], _ from: Int) -> [[Int]] {
        let piece = board[from]
        var out: [[Int]] = []
        for (dr, dc) in directions(piece) {
            let r = Checkers.row(from) + dr
            let c = Checkers.col(from) + dc
            if onBoard(r, c) && board[Checkers.square(r, c)] == 0 { out.append([from, Checkers.square(r, c)]) }
        }
        return out
    }

    /// All legal moves for the side to move. If any piece can jump, only jumps are legal.
    static func legalMoves(_ pos: CheckersPosition) -> [CheckersMove] {
        var jumps: [CheckersMove] = []
        var steps: [CheckersMove] = []
        for sq in 0..<64 {
            let p = pos.board[sq]
            if p == 0 || Checkers.isRed(p) != pos.redToMove { continue }
            for j in jumpsFrom(pos.board, sq) { jumps.append(CheckersMove(path: j)) }
            if jumps.isEmpty { for s in stepsFrom(pos.board, sq) { steps.append(CheckersMove(path: s)) } }
        }
        return jumps.isEmpty ? steps : jumps
    }

    /// Returns the position after `move`, which must be one of legalMoves.
    static func apply(_ pos: CheckersPosition, _ move: CheckersMove) -> CheckersPosition {
        var next = pos
        let piece = next.board[move.from]
        let captures = move.captured()
        next.board[move.from] = 0
        for c in captures { next.board[c] = 0 }
        let crowned = (piece == Checkers.redMan && Checkers.row(move.to) == 0) ||
            (piece == Checkers.blackMan && Checkers.row(move.to) == 7)
        next.board[move.to] = crowned ? (piece > 0 ? Checkers.redKing : Checkers.blackKing) : piece
        next.quietPlies = (!captures.isEmpty || !Checkers.isKing(piece)) ? 0 : pos.quietPlies + 1
        next.redToMove = !pos.redToMove
        return next
    }

    /// The move in legalMoves equal to `received`, or nil (used for moves from the other phone).
    static func validate(_ pos: CheckersPosition, _ received: CheckersMove) -> CheckersMove? {
        legalMoves(pos).first { $0.path == received.path }
    }

    /// `repeats` is how many times the current position has already occurred in the game (including now).
    static func result(_ pos: CheckersPosition, repeats: Int = 1) -> CheckersResult {
        if legalMoves(pos).isEmpty { return pos.redToMove ? .blackWins : .redWins }
        if pos.quietPlies >= Checkers.drawPlies || repeats >= 3 { return .draw }
        return .ongoing
    }

    static func count(_ pos: CheckersPosition, red: Bool) -> Int {
        pos.board.filter { $0 != 0 && Checkers.isRed($0) == red }.count
    }
}

/// A small seedable random source (SplitMix64) so the bot can be tested with a fixed seed.
struct CheckersRng {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

/// The computer opponent: an alpha-beta search on material, crowning and how far
/// the men have advanced. The difficulty is the search depth; EASY also plays a
/// random legal move now and then so it can be beaten by a beginner.
enum CheckersBot {
    private static let man = 100
    private static let king = 175
    private static let win = 100_000

    static func depthFor(_ difficulty: String) -> Int {
        switch difficulty {
        case "HARD": return 8
        case "MEDIUM": return 5
        default: return 2
        }
    }

    static func chooseMove(_ pos: CheckersPosition, difficulty: String, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) -> CheckersMove? {
        var rng = CheckersRng(seed: seed)
        let moves = CheckersRules.legalMoves(pos)
        if moves.isEmpty { return nil }
        if moves.count == 1 { return moves[0] }
        if difficulty != "HARD" && difficulty != "MEDIUM" && rng.int(100) < 25 { return moves[rng.int(moves.count)] }
        let depth = depthFor(difficulty)
        // Shuffle so equal-scoring moves are not always the first one found.
        var order = moves
        var i = order.count - 1
        while i > 0 { order.swapAt(i, rng.int(i + 1)); i -= 1 }
        var best = order[0]
        var bestScore = Int.min
        for m in order {
            let score = -search(CheckersRules.apply(pos, m), depth - 1, -win * 2, win * 2)
            if score > bestScore { bestScore = score; best = m }
        }
        return best
    }

    /// Score for the side to move in `pos`; higher is better for them.
    private static func search(_ pos: CheckersPosition, _ depth: Int, _ alphaIn: Int, _ beta: Int) -> Int {
        let moves = CheckersRules.legalMoves(pos)
        if moves.isEmpty { return -win - depth }          // the side to move has lost; sooner is worse
        if pos.quietPlies >= Checkers.drawPlies { return 0 }
        if depth <= 0 { return evaluate(pos) }
        var alpha = alphaIn
        var best = Int.min
        // Captures first makes the pruning work much better.
        for m in moves.sorted(by: { $0.path.count > $1.path.count }) {
            let score = -search(CheckersRules.apply(pos, m), depth - 1, -beta, -alpha)
            if score > best { best = score }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }
        return best
    }

    private static func evaluate(_ pos: CheckersPosition) -> Int {
        var red = 0
        var black = 0
        for sq in 0..<64 {
            let p = pos.board[sq]
            if p == 0 { continue }
            let r = Checkers.row(sq)
            let value = Checkers.isKing(p) ? king : man + (p > 0 ? 7 - r : r) * 3
            if p > 0 { red += value } else { black += value }
        }
        let diff = red - black
        return pos.redToMove ? diff : -diff
    }
}
