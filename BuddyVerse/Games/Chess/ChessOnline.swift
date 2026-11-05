import Foundation

/// Mirrors ChessOnline.kt: the text messages two phones send each other during
/// an online chess game, kept apart from the screen so the rules for them are
/// easy to check. Every message is "<round>:<kind>[:details]", the same
/// round-tag idea Tic-Tac-Toe uses so a message still in flight when a new
/// game starts is dropped instead of being applied to the fresh board:
///   - "<round>:MOVE:<from>:<to>:<promo>"  a move (squares 0..63, promo 0 or 2..5)
///   - "<round>:RESIGN"                    the sender gives up this game
///   - "<round>:RESET"                     start a new game (round + 1)
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

    var round: Int {
        switch self {
        case .move(let round, _): return round
        case .resign(let round): return round
        case .reset(let round): return round
        }
    }
}

enum ChessWire {
    static func move(_ round: Int, _ m: ChessMove) -> String { "\(round):MOVE:\(m.from):\(m.to):\(m.promo)" }
    static func resign(_ round: Int) -> String { "\(round):RESIGN" }
    static func reset(_ round: Int) -> String { "\(round):RESET" }

    /// Reads a raw message; anything malformed or out of range gives nil.
    static func parse(_ raw: String) -> ChessWireMessage? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let round = Int(first), round >= 0, parts.count >= 2 else { return nil }
        switch parts[1] {
        case "RESIGN":
            if parts.count == 2 { return ChessWireMessage.resign(round: round) }
            return nil
        case "RESET":
            if parts.count == 2 { return ChessWireMessage.reset(round: round) }
            return nil
        case "MOVE":
            guard parts.count == 5,
                  let from = Int(parts[2]), let to = Int(parts[3]), let promo = Int(parts[4]) else { return nil }
            guard (0...63).contains(from), (0...63).contains(to) else { return nil }
            guard promo == 0 || (Chess.knight...Chess.queen).contains(promo) else { return nil }
            return ChessWireMessage.move(round: round, move: ChessMove(from: from, to: to, promo: promo))
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
