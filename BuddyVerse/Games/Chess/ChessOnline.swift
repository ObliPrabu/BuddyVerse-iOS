import Foundation

/// Mirrors ChessOnline.kt: the text messages two phones send each other during
/// an online chess game, kept apart from the screen so the rules for them are
/// easy to check. Every message is "<round>:<kind>[:details]", the same
/// round-tag idea Tic-Tac-Toe uses so a message still in flight when a new
/// game starts is dropped instead of being applied to the fresh board:
///   - "<round>:MOVE:<from>:<to>:<promo>"  a move (squares 0..63, promo 0 or 2..5)
///   - "<round>:RESIGN"                    the sender gives up this game
///   - "<round>:RESET"                     start a new game (round + 1). Only believed if the
///                                         game is already over, or this player just agreed to
///                                         a NEWGAME proposal - nobody can wipe a game in
///                                         progress on their own.
///   - "<round>:NEWGAME" / "NEWNO"         propose a new game mid-game / turn the proposal down.
///                                         The player who accepts sends the RESET.
///   - "<round>:CLOCK:<seconds>"           the host's chosen time per player (0 = no clock),
///                                         sent once at the start of the match
///   - "<round>:TIMEOUT"                   the sender's own clock ran out, so the sender lost
///   - "<round>:DRAW" / "DRAWOK" / "DRAWNO" offer a draw, accept it, decline it. Nothing
///                                         changes until the other player says DRAWOK.
///   - "<round>:TAKEBACK:<ply>" / "TBOK:<ply>" / "TBNO:<ply>"  ask to undo the sender's own
///                                         last move, accept it, decline it. <ply> is how many
///                                         moves had been played, so a request that crosses
///                                         a move in the post is recognised as stale.
///
/// Who plays White is not negotiated with a HELLO handshake. The room's
/// player list already puts the host in seat 0 and the guest in seat 1 on
/// both phones, so seat (round % 2) plays White: seat 0 in round 0, then the
/// colours swap on every new game. This must stay identical to Android, or a
/// mixed iOS/Android room would disagree about whose move it is.
///
/// Nothing a peer sends is trusted. A MOVE is only applied if it is the
/// sender's turn and it is exactly one of ChessRules.legalMoves for the
/// current position.
enum ChessWireMessage: Equatable {
    case move(round: Int, move: ChessMove)
    case resign(round: Int)
    case reset(round: Int)
    case newGameOffer(round: Int)
    case newGameDecline(round: Int)
    case clock(round: Int, seconds: Int)
    case timeout(round: Int)
    case drawOffer(round: Int)
    case drawAccept(round: Int)
    case drawDecline(round: Int)
    case takebackRequest(round: Int, ply: Int)
    case takebackAccept(round: Int, ply: Int)
    case takebackDecline(round: Int, ply: Int)

    var round: Int {
        switch self {
        case .move(let round, _): return round
        case .resign(let round): return round
        case .reset(let round): return round
        case .newGameOffer(let round): return round
        case .newGameDecline(let round): return round
        case .clock(let round, _): return round
        case .timeout(let round): return round
        case .drawOffer(let round): return round
        case .drawAccept(let round): return round
        case .drawDecline(let round): return round
        case .takebackRequest(let round, _): return round
        case .takebackAccept(let round, _): return round
        case .takebackDecline(let round, _): return round
        }
    }
}

/// The time-per-player choice the host makes on the lobby screen. It is handed
/// to the chess screen through here because the lobby and the chess screen are
/// separated by the rules and instructions screens. Only the host's value is
/// ever used: the guest learns the setting from the CLOCK message instead.
enum ChessSettings {
    nonisolated(unsafe) static var hostClockSeconds = 0
    /// The time controls the lobby offers; anything else received is rejected.
    static let allowedClockSeconds: Set<Int> = [0, 180, 300, 600]
}

/// Both players' remaining time. It does no timing of its own: the caller
/// passes in "now" (milliseconds), so it can be unit tested without waiting.
/// Only the side to move has a running clock, and nothing runs before White's
/// first move, so nobody loses time to the opening pause.
final class ChessClock {
    let totalMs: Int64
    private var whiteBase: Int64
    private var blackBase: Int64
    // true = White's clock runs, false = Black's, nil = stopped.
    private var running: Bool?
    private var since: Int64 = 0

    init(totalMs: Int64) {
        self.totalMs = totalMs
        self.whiteBase = totalMs
        self.blackBase = totalMs
    }

    /// Time left for a side right now. May go below zero if nobody has checked in time.
    func remaining(white: Bool, now: Int64) -> Int64 {
        let base = white ? whiteBase : blackBase
        return running == white ? base - (now - since) : base
    }

    /// Charges the running clock for the time it used, then starts `white`'s clock (or stops all if nil).
    func switchTo(_ white: Bool?, now: Int64) {
        if let r = running {
            if r { whiteBase -= now - since } else { blackBase -= now - since }
        }
        running = white
        since = now
    }

    func stop(now: Int64) { switchTo(nil, now: now) }
}

enum ChessWire {
    /// A game can't realistically pass this many moves; anything bigger is junk.
    static let maxPly = 1000

    static func move(_ round: Int, _ m: ChessMove) -> String { "\(round):MOVE:\(m.from):\(m.to):\(m.promo)" }
    static func resign(_ round: Int) -> String { "\(round):RESIGN" }
    static func reset(_ round: Int) -> String { "\(round):RESET" }
    static func newGameOffer(_ round: Int) -> String { "\(round):NEWGAME" }
    static func newGameDecline(_ round: Int) -> String { "\(round):NEWNO" }
    static func clock(_ round: Int, _ seconds: Int) -> String { "\(round):CLOCK:\(seconds)" }
    static func timeout(_ round: Int) -> String { "\(round):TIMEOUT" }
    static func drawOffer(_ round: Int) -> String { "\(round):DRAW" }
    static func drawAccept(_ round: Int) -> String { "\(round):DRAWOK" }
    static func drawDecline(_ round: Int) -> String { "\(round):DRAWNO" }
    static func takeback(_ round: Int, _ ply: Int) -> String { "\(round):TAKEBACK:\(ply)" }
    static func takebackAccept(_ round: Int, _ ply: Int) -> String { "\(round):TBOK:\(ply)" }
    static func takebackDecline(_ round: Int, _ ply: Int) -> String { "\(round):TBNO:\(ply)" }

    /// Reads a raw message; anything malformed or out of range gives nil.
    static func parse(_ raw: String) -> ChessWireMessage? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let round = Int(first), round >= 0, parts.count >= 2 else { return nil }
        switch parts[1] {
        case "RESIGN":
            return parts.count == 2 ? .resign(round: round) : nil
        case "RESET":
            return parts.count == 2 ? .reset(round: round) : nil
        case "NEWGAME":
            return parts.count == 2 ? .newGameOffer(round: round) : nil
        case "NEWNO":
            return parts.count == 2 ? .newGameDecline(round: round) : nil
        case "TIMEOUT":
            return parts.count == 2 ? .timeout(round: round) : nil
        case "DRAW":
            return parts.count == 2 ? .drawOffer(round: round) : nil
        case "DRAWOK":
            return parts.count == 2 ? .drawAccept(round: round) : nil
        case "DRAWNO":
            return parts.count == 2 ? .drawDecline(round: round) : nil
        case "CLOCK":
            guard parts.count == 3, let seconds = Int(parts[2]),
                  ChessSettings.allowedClockSeconds.contains(seconds) else { return nil }
            return .clock(round: round, seconds: seconds)
        case "TAKEBACK", "TBOK", "TBNO":
            guard parts.count == 3, let ply = Int(parts[2]), (1...maxPly).contains(ply) else { return nil }
            switch parts[1] {
            case "TAKEBACK": return .takebackRequest(round: round, ply: ply)
            case "TBOK": return .takebackAccept(round: round, ply: ply)
            default: return .takebackDecline(round: round, ply: ply)
            }
        case "MOVE":
            guard parts.count == 5,
                  let from = Int(parts[2]), let to = Int(parts[3]), let promo = Int(parts[4]) else { return nil }
            guard (0...63).contains(from), (0...63).contains(to) else { return nil }
            guard promo == 0 || (Chess.knight...Chess.queen).contains(promo) else { return nil }
            return .move(round: round, move: ChessMove(from: from, to: to, promo: promo))
        default:
            return nil
        }
    }

    /// Returns the real legal move equal to the one received, or nil if it is
    /// not legal in this position (wrong piece, leaves the king in check, a
    /// promotion type on a non-promotion, and so on).
    static func validate(_ pos: ChessPosition, _ received: ChessMove) -> ChessMove? {
        ChessRules.legalMoves(pos).first { $0 == received }
    }

    /// Which seat (0 = host, 1 = guest) plays White in the given round.
    static func whiteSeat(_ round: Int) -> Int { round % 2 }

    /// The seat whose turn it is at this position in this round.
    static func seatToMove(_ pos: ChessPosition, round: Int) -> Int {
        pos.whiteToMove ? whiteSeat(round) : 1 - whiteSeat(round)
    }

    /// Only a small jump forward is believed, like Tic-Tac-Toe (ISSUE-120).
    static func acceptableResetRound(current: Int, received: Int) -> Bool {
        received >= current + 1 && received <= current + 3
    }
}
