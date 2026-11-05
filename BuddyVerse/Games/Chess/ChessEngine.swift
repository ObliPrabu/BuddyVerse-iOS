import Foundation

/// Mirrors ChessEngine.kt: chess rules and a small computer opponent, written
/// from scratch (no chess library, so no outside licence terms). The board is a
/// flat array of 64 squares. Index 0 is the top-left corner as White sees the
/// board (a8) and index 63 is the bottom-right (h1), so `row = index / 8`
/// counts down from Black's back rank and `col = index % 8` counts a..h. A
/// positive number is a White piece, a negative number a Black piece, and the
/// size of the number says which piece it is. Square numbers are part of the
/// online wire format (ChessOnline.swift), so they must stay identical to
/// Android's.
enum Chess {
    static let empty = 0
    static let pawn = 1
    static let knight = 2
    static let bishop = 3
    static let rook = 4
    static let queen = 5
    static let king = 6

    // Castling rights are one bit each, kept in ChessPosition.castle.
    static let castleWK = 1
    static let castleWQ = 2
    static let castleBK = 4
    static let castleBQ = 8

    static let startFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
}

/// One move. `promo` is the piece type a pawn becomes (2...5), or 0 for no promotion.
struct ChessMove: Hashable {
    let from: Int
    let to: Int
    var promo: Int = 0
}

/// Everything needed to know what can happen next in a game.
struct ChessPosition {
    var board: [Int] = Array(repeating: 0, count: 64)
    var whiteToMove = true
    var castle = 0
    // The square a pawn just skipped over with a two-step move (the square an
    // en passant capture would land on), or -1.
    var ep = -1
    // Moves since the last capture or pawn move, for the fifty-move rule.
    var halfmove = 0

    /// Identical keys mean the same position, used to spot threefold repetition.
    func key() -> String {
        var s = ""
        s.reserveCapacity(80)
        for p in board { s.append(Character(UnicodeScalar(UInt8(p + 6 + 97)))) }
        s.append(whiteToMove ? "w" : "b")
        s.append(String(castle))
        s.append(",")
        s.append(String(ep))
        return s
    }

    static func start() -> ChessPosition { fromFen(Chess.startFen) }

    /// Reads standard FEN text.
    static func fromFen(_ fen: String) -> ChessPosition {
        let parts = fen.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        var pos = ChessPosition()
        var sq = 0
        for ch in parts[0] {
            if ch == "/" { continue }
            if let n = ch.wholeNumberValue {
                sq += n
            } else {
                let letters: [Character] = ["p", "n", "b", "r", "q", "k"]
                let type = (letters.firstIndex(of: Character(ch.lowercased())) ?? 0) + 1
                pos.board[sq] = ch.isUppercase ? type : -type
                sq += 1
            }
        }
        pos.whiteToMove = (parts.count > 1 ? parts[1] : "w") == "w"
        let rights = parts.count > 2 ? parts[2] : "-"
        if rights.contains("K") { pos.castle |= Chess.castleWK }
        if rights.contains("Q") { pos.castle |= Chess.castleWQ }
        if rights.contains("k") { pos.castle |= Chess.castleBK }
        if rights.contains("q") { pos.castle |= Chess.castleBQ }
        let epText = parts.count > 3 ? parts[3] : "-"
        if epText.count == 2 {
            let chars = Array(epText)
            if let rank = chars[1].wholeNumberValue, let file = chars[0].asciiValue {
                pos.ep = (8 - rank) * 8 + Int(file) - 97
            }
        }
        pos.halfmove = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
        return pos
    }
}

enum ChessStatus { case ongoing, checkmate, stalemate, drawMaterial, drawFifty }

enum ChessRules {
    private static let knightSteps = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
    private static let kingSteps = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    private static let diagonals = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    private static let straights = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    private static func onBoard(_ r: Int, _ c: Int) -> Bool { r >= 0 && r <= 7 && c >= 0 && c <= 7 }

    /// True if a piece of the given colour could capture on `sq` right now.
    static func isAttacked(_ b: [Int], _ sq: Int, byWhite: Bool) -> Bool {
        let sign = byWhite ? 1 : -1
        let r = sq / 8
        let c = sq % 8

        // A White pawn attacks upward (toward row 0), so it sits one row below the target.
        let pawnRow = byWhite ? r + 1 : r - 1
        if pawnRow >= 0 && pawnRow <= 7 {
            if c > 0 && b[pawnRow * 8 + c - 1] == sign * Chess.pawn { return true }
            if c < 7 && b[pawnRow * 8 + c + 1] == sign * Chess.pawn { return true }
        }
        for s in knightSteps {
            let nr = r + s.0, nc = c + s.1
            if onBoard(nr, nc) && b[nr * 8 + nc] == sign * Chess.knight { return true }
        }
        for s in kingSteps {
            let nr = r + s.0, nc = c + s.1
            if onBoard(nr, nc) && b[nr * 8 + nc] == sign * Chess.king { return true }
        }
        for d in diagonals {
            var nr = r + d.0, nc = c + d.1
            while onBoard(nr, nc) {
                let p = b[nr * 8 + nc]
                if p != 0 {
                    if p == sign * Chess.bishop || p == sign * Chess.queen { return true }
                    break
                }
                nr += d.0
                nc += d.1
            }
        }
        for d in straights {
            var nr = r + d.0, nc = c + d.1
            while onBoard(nr, nc) {
                let p = b[nr * 8 + nc]
                if p != 0 {
                    if p == sign * Chess.rook || p == sign * Chess.queen { return true }
                    break
                }
                nr += d.0
                nc += d.1
            }
        }
        return false
    }

    static func kingSquare(_ b: [Int], white: Bool) -> Int {
        let king = white ? Chess.king : -Chess.king
        for i in 0..<64 where b[i] == king { return i }
        return -1
    }

    static func inCheck(_ pos: ChessPosition, white: Bool) -> Bool {
        let k = kingSquare(pos.board, white: white)
        return k >= 0 && isAttacked(pos.board, k, byWhite: !white)
    }

    private static func addPawnMove(_ out: inout [ChessMove], _ from: Int, _ to: Int, promotes: Bool) {
        if promotes {
            out.append(ChessMove(from: from, to: to, promo: Chess.queen))
            out.append(ChessMove(from: from, to: to, promo: Chess.rook))
            out.append(ChessMove(from: from, to: to, promo: Chess.bishop))
            out.append(ChessMove(from: from, to: to, promo: Chess.knight))
        } else {
            out.append(ChessMove(from: from, to: to))
        }
    }

    /// Every move the piece movement rules allow, including ones that leave your own king in check.
    private static func pseudoMoves(_ pos: ChessPosition) -> [ChessMove] {
        var out: [ChessMove] = []
        out.reserveCapacity(48)
        let white = pos.whiteToMove
        let b = pos.board
        for sq in 0..<64 {
            let p = b[sq]
            if p == 0 || (p > 0) != white { continue }
            let r = sq / 8
            let c = sq % 8
            switch abs(p) {
            case Chess.pawn:
                let dir = white ? -1 : 1
                let startRow = white ? 6 : 1
                let lastRow = white ? 0 : 7
                let r1 = r + dir
                if r1 >= 0 && r1 <= 7 {
                    if b[r1 * 8 + c] == 0 {
                        addPawnMove(&out, sq, r1 * 8 + c, promotes: r1 == lastRow)
                        if r == startRow && b[(r + 2 * dir) * 8 + c] == 0 {
                            out.append(ChessMove(from: sq, to: (r + 2 * dir) * 8 + c))
                        }
                    }
                    for dc in [-1, 1] {
                        let nc = c + dc
                        if nc < 0 || nc > 7 { continue }
                        let to = r1 * 8 + nc
                        let target = b[to]
                        if (target != 0 && (target > 0) != white) || to == pos.ep {
                            addPawnMove(&out, sq, to, promotes: r1 == lastRow)
                        }
                    }
                }
            case Chess.knight:
                for s in knightSteps {
                    let nr = r + s.0, nc = c + s.1
                    if !onBoard(nr, nc) { continue }
                    let t = b[nr * 8 + nc]
                    if t == 0 || (t > 0) != white { out.append(ChessMove(from: sq, to: nr * 8 + nc)) }
                }
            case Chess.king:
                for s in kingSteps {
                    let nr = r + s.0, nc = c + s.1
                    if !onBoard(nr, nc) { continue }
                    let t = b[nr * 8 + nc]
                    if t == 0 || (t > 0) != white { out.append(ChessMove(from: sq, to: nr * 8 + nc)) }
                }
                addCastling(pos, sq, &out)
            default:
                let type = abs(p)
                if type != Chess.rook { slide(b, sq, white, diagonals, &out) }
                if type != Chess.bishop { slide(b, sq, white, straights, &out) }
            }
        }
        return out
    }

    private static func slide(_ b: [Int], _ sq: Int, _ white: Bool, _ dirs: [(Int, Int)], _ out: inout [ChessMove]) {
        let r = sq / 8
        let c = sq % 8
        for d in dirs {
            var nr = r + d.0, nc = c + d.1
            while onBoard(nr, nc) {
                let t = b[nr * 8 + nc]
                if t == 0 {
                    out.append(ChessMove(from: sq, to: nr * 8 + nc))
                } else {
                    if (t > 0) != white { out.append(ChessMove(from: sq, to: nr * 8 + nc)) }
                    break
                }
                nr += d.0
                nc += d.1
            }
        }
    }

    // Castling needs: the rights still held, empty squares between king and
    // rook, and the king not starting in, passing through, or landing in check.
    private static func addCastling(_ pos: ChessPosition, _ sq: Int, _ out: inout [ChessMove]) {
        let b = pos.board
        if pos.whiteToMove && sq == 60 {
            if pos.castle & Chess.castleWK != 0 && b[61] == 0 && b[62] == 0 && b[63] == Chess.rook &&
                !isAttacked(b, 60, byWhite: false) && !isAttacked(b, 61, byWhite: false) && !isAttacked(b, 62, byWhite: false) {
                out.append(ChessMove(from: 60, to: 62))
            }
            if pos.castle & Chess.castleWQ != 0 && b[59] == 0 && b[58] == 0 && b[57] == 0 && b[56] == Chess.rook &&
                !isAttacked(b, 60, byWhite: false) && !isAttacked(b, 59, byWhite: false) && !isAttacked(b, 58, byWhite: false) {
                out.append(ChessMove(from: 60, to: 58))
            }
        } else if !pos.whiteToMove && sq == 4 {
            if pos.castle & Chess.castleBK != 0 && b[5] == 0 && b[6] == 0 && b[7] == -Chess.rook &&
                !isAttacked(b, 4, byWhite: true) && !isAttacked(b, 5, byWhite: true) && !isAttacked(b, 6, byWhite: true) {
                out.append(ChessMove(from: 4, to: 6))
            }
            if pos.castle & Chess.castleBQ != 0 && b[3] == 0 && b[2] == 0 && b[1] == 0 && b[0] == -Chess.rook &&
                !isAttacked(b, 4, byWhite: true) && !isAttacked(b, 3, byWhite: true) && !isAttacked(b, 2, byWhite: true) {
                out.append(ChessMove(from: 4, to: 2))
            }
        }
    }

    /// Returns the position after the move. The input position is not changed.
    static func apply(_ pos: ChessPosition, _ m: ChessMove) -> ChessPosition {
        var next = pos
        let piece = next.board[m.from]
        let type = abs(piece)
        let white = piece > 0
        let captured = next.board[m.to]

        // En passant: the pawn moved diagonally onto an empty square, so the
        // pawn it captures is beside it on the row it started from.
        if type == Chess.pawn && m.to == pos.ep && captured == 0 && m.from % 8 != m.to % 8 {
            next.board[(m.from / 8) * 8 + m.to % 8] = 0
        }

        next.board[m.to] = m.promo != 0 ? (white ? m.promo : -m.promo) : piece
        next.board[m.from] = 0

        // Castling also moves the rook.
        if type == Chess.king && abs(m.to - m.from) == 2 {
            let row = m.from / 8
            if m.to % 8 == 6 {
                next.board[row * 8 + 5] = next.board[row * 8 + 7]
                next.board[row * 8 + 7] = 0
            } else {
                next.board[row * 8 + 3] = next.board[row * 8]
                next.board[row * 8] = 0
            }
        }

        if type == Chess.king {
            let mask = white ? (Chess.castleWK | Chess.castleWQ) : (Chess.castleBK | Chess.castleBQ)
            next.castle &= ~mask
        }
        // A rook leaving its corner, or being captured there, ends that side's right.
        for s in [m.from, m.to] {
            switch s {
            case 0: next.castle &= ~Chess.castleBQ
            case 7: next.castle &= ~Chess.castleBK
            case 56: next.castle &= ~Chess.castleWQ
            case 63: next.castle &= ~Chess.castleWK
            default: break
            }
        }

        next.ep = (type == Chess.pawn && abs(m.to - m.from) == 16) ? (m.from + m.to) / 2 : -1
        next.halfmove = (type == Chess.pawn || captured != 0) ? 0 : pos.halfmove + 1
        next.whiteToMove = !pos.whiteToMove
        return next
    }

    /// Every move the side to move may actually play.
    static func legalMoves(_ pos: ChessPosition) -> [ChessMove] {
        let mover = pos.whiteToMove
        var out: [ChessMove] = []
        out.reserveCapacity(40)
        for m in pseudoMoves(pos) where !inCheck(apply(pos, m), white: mover) {
            out.append(m)
        }
        return out
    }

    static func insufficientMaterial(_ b: [Int]) -> Bool {
        var minors = 0
        for p in b {
            switch abs(p) {
            case Chess.pawn, Chess.rook, Chess.queen: return false
            case Chess.knight, Chess.bishop: minors += 1
            default: break
            }
        }
        return minors <= 1
    }

    /// Checkmate, stalemate and the automatic draws. Threefold repetition is tracked by the caller.
    static func status(_ pos: ChessPosition, legal: [ChessMove]? = nil) -> ChessStatus {
        let moves = legal ?? legalMoves(pos)
        if moves.isEmpty {
            return inCheck(pos, white: pos.whiteToMove) ? .checkmate : .stalemate
        }
        if insufficientMaterial(pos.board) { return .drawMaterial }
        if pos.halfmove >= 100 { return .drawFifty }
        return .ongoing
    }
}

/// The computer opponent: a short alpha-beta search, plus plain random play on Easy.
enum ChessBot {
    private static let mate = 100000
    private static let value = [0, 100, 320, 330, 500, 900, 0]

    static func choose(_ pos: ChessPosition, difficulty: String) -> ChessMove? {
        let moves = ChessRules.legalMoves(pos)
        if moves.isEmpty { return nil }
        switch difficulty {
        case "HARD": return search(pos, moves, maxDepth: 3, millis: 3_000)
        case "MEDIUM": return search(pos, moves, maxDepth: 2, millis: 2_000)
        default:
            // Easy: mostly random, but it grabs a free capture about half the time.
            let captures = moves.filter { pos.board[$0.to] != 0 }
            if !captures.isEmpty && Bool.random() { return captures.randomElement() }
            return moves.randomElement()
        }
    }

    private final class Clock {
        let deadline: UInt64
        var expired = false
        init(deadline: UInt64) { self.deadline = deadline }
        func check() {
            if DispatchTime.now().uptimeNanoseconds > deadline { expired = true }
        }
    }

    // Searches one level deeper at a time so a slow phone can stop on the
    // time limit and still play the best move from the last finished level.
    private static func search(_ pos: ChessPosition, _ moves: [ChessMove], maxDepth: Int, millis: UInt64) -> ChessMove {
        let clock = Clock(deadline: DispatchTime.now().uptimeNanoseconds + millis * 1_000_000)
        var best = moves.randomElement()!
        // Shuffling first means equally good moves are picked at random.
        var ordered = moves.shuffled().sorted { orderScore(pos, $0) > orderScore(pos, $1) }
        for depth in 1...maxDepth {
            var alpha = -mate - 1
            var bestThisDepth: ChessMove?
            for m in ordered {
                let score = -negamax(ChessRules.apply(pos, m), depth - 1, -mate - 1, -alpha, 1, clock)
                if clock.expired { break }
                if score > alpha {
                    alpha = score
                    bestThisDepth = m
                }
            }
            if clock.expired { break }
            if let b = bestThisDepth {
                best = b
                // Try the best move first at the next level, so more of the tree gets skipped.
                ordered = [b] + ordered.filter { $0 != b }
            }
        }
        return best
    }

    private static func orderScore(_ pos: ChessPosition, _ m: ChessMove) -> Int {
        let victim = abs(pos.board[m.to])
        let mover = abs(pos.board[m.from])
        var s = 0
        if victim != 0 { s += value[victim] * 10 - value[mover] }
        if m.promo != 0 { s += value[m.promo] }
        return s
    }

    private static func negamax(_ pos: ChessPosition, _ depth: Int, _ alphaIn: Int, _ beta: Int, _ ply: Int, _ clock: Clock) -> Int {
        clock.check()
        if clock.expired { return 0 }
        var alpha = alphaIn
        let moves = ChessRules.legalMoves(pos)
        if moves.isEmpty {
            return ChessRules.inCheck(pos, white: pos.whiteToMove) ? -(mate - ply) : 0
        }
        if pos.halfmove >= 100 || ChessRules.insufficientMaterial(pos.board) { return 0 }
        if depth <= 0 { return quiesce(pos, alpha, beta, 0, clock) }
        for m in moves.sorted(by: { orderScore(pos, $0) > orderScore(pos, $1) }) {
            let score = -negamax(ChessRules.apply(pos, m), depth - 1, -beta, -alpha, ply + 1, clock)
            if clock.expired { return 0 }
            if score >= beta { return beta }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    // At the end of the search, keep playing out captures so the bot doesn't
    // grab a piece that is immediately taken back.
    private static func quiesce(_ pos: ChessPosition, _ alphaIn: Int, _ beta: Int, _ depth: Int, _ clock: Clock) -> Int {
        var alpha = alphaIn
        let standPat = evaluate(pos)
        if standPat >= beta { return beta }
        if standPat > alpha { alpha = standPat }
        if depth >= 4 { return alpha }
        clock.check()
        if clock.expired { return 0 }
        let captures = ChessRules.legalMoves(pos).filter { pos.board[$0.to] != 0 }
        for m in captures.sorted(by: { orderScore(pos, $0) > orderScore(pos, $1) }) {
            let score = -quiesce(ChessRules.apply(pos, m), -beta, -alpha, depth + 1, clock)
            if clock.expired { return 0 }
            if score >= beta { return beta }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    /// Score from the side-to-move's point of view: material plus a little positional sense.
    private static func evaluate(_ pos: ChessPosition) -> Int {
        var score = 0
        for sq in 0..<64 {
            let p = pos.board[sq]
            if p == 0 { continue }
            let type = abs(p)
            let r = sq / 8
            let c = sq % 8
            let centre = 7 - max(abs(2 * r - 7), abs(2 * c - 7))
            var v = value[type]
            switch type {
            case Chess.pawn:
                let advanced = p > 0 ? 6 - r : r - 1
                v += advanced * 8 + ((c == 3 || c == 4) ? 5 : 0)
            case Chess.knight, Chess.bishop: v += centre * 3
            case Chess.queen: v += centre
            default: break
            }
            score += p > 0 ? v : -v
        }
        return pos.whiteToMove ? score : -score
    }
}
