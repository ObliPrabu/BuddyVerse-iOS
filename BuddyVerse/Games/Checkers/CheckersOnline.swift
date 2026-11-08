import Foundation

/// Mirrors CheckersOnline.kt: the text messages two phones send each other
/// during an online checkers game. Every message is "<round>:<kind>[:details]",
/// the same round-tag idea chess and Tic-Tac-Toe use, so a message still in
/// flight when a new game starts is dropped instead of being applied to the
/// fresh board:
///   - "<round>:MOVE:<squares>"   a whole move as dash-joined squares, e.g. "42-33-24"
///   - "<round>:RESIGN"           the sender gives up this game
///   - "<round>:RESET"            start a new game (round + 1); only believed if the game is over or this player agreed
///   - "<round>:NEWGAME" / "NEWNO" propose a new game mid-game / turn the proposal down
///   - "<round>:DRAW" / "DRAWOK" / "DRAWNO"  offer a draw, accept it, decline it
///
/// Seat (round % 2) plays Red and moves first: seat 0 (the host) in round 0,
/// then the colours swap on every new game. This must stay identical to
/// Android, or a mixed iOS/Android room would disagree about whose move it is.
/// Nothing a peer sends is trusted: a MOVE is only applied if it is the
/// sender's turn and exactly one of CheckersRules.legalMoves.
enum CheckersWireMessage: Equatable {
    case move(round: Int, move: CheckersMove)
    case resign(round: Int)
    case reset(round: Int)
    case newGameOffer(round: Int)
    case newGameDecline(round: Int)
    case drawOffer(round: Int)
    case drawAccept(round: Int)
    case drawDecline(round: Int)

    var round: Int {
        switch self {
        case .move(let r, _), .resign(let r), .reset(let r), .newGameOffer(let r), .newGameDecline(let r),
             .drawOffer(let r), .drawAccept(let r), .drawDecline(let r):
            return r
        }
    }
}

enum CheckersWire {
    static func move(_ round: Int, _ m: CheckersMove) -> String { "\(round):MOVE:\(m.toWire())" }
    static func resign(_ round: Int) -> String { "\(round):RESIGN" }
    static func reset(_ round: Int) -> String { "\(round):RESET" }
    static func newGameOffer(_ round: Int) -> String { "\(round):NEWGAME" }
    static func newGameDecline(_ round: Int) -> String { "\(round):NEWNO" }
    static func drawOffer(_ round: Int) -> String { "\(round):DRAW" }
    static func drawAccept(_ round: Int) -> String { "\(round):DRAWOK" }
    static func drawDecline(_ round: Int) -> String { "\(round):DRAWNO" }

    /// Reads a raw message; anything malformed or out of range gives nil.
    static func parse(_ raw: String) -> CheckersWireMessage? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let round = Int(first), round >= 0, parts.count >= 2 else { return nil }
        switch parts[1] {
        case "RESIGN": return parts.count == 2 ? .resign(round: round) : nil
        case "RESET": return parts.count == 2 ? .reset(round: round) : nil
        case "NEWGAME": return parts.count == 2 ? .newGameOffer(round: round) : nil
        case "NEWNO": return parts.count == 2 ? .newGameDecline(round: round) : nil
        case "DRAW": return parts.count == 2 ? .drawOffer(round: round) : nil
        case "DRAWOK": return parts.count == 2 ? .drawAccept(round: round) : nil
        case "DRAWNO": return parts.count == 2 ? .drawDecline(round: round) : nil
        case "MOVE":
            guard parts.count == 3, let m = CheckersMove.fromWire(parts[2]) else { return nil }
            return .move(round: round, move: m)
        default: return nil
        }
    }

    /// Which seat (0 = host, 1 = guest) plays Red in the given round.
    static func redSeat(_ round: Int) -> Int { round % 2 }

    /// The seat whose turn it is at this position in this round.
    static func seatToMove(_ pos: CheckersPosition, round: Int) -> Int {
        pos.redToMove ? redSeat(round) : 1 - redSeat(round)
    }

    /// Only a small jump forward is believed, like the other online games.
    static func acceptableResetRound(current: Int, received: Int) -> Bool {
        received >= current + 1 && received <= current + 3
    }
}
