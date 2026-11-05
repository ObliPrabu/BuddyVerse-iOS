import XCTest

/// Mirrors ChessWireTest.kt: checks the online chess message format and that
/// bad moves are refused. Android and iOS share one Firestore room, so the
/// strings and rules asserted here must stay identical on both platforms.
final class ChessWireTests: XCTestCase {
    // Squares are numbered 0 = a8 ... 63 = h1: e2 = 52, e4 = 36, e7 = 12, e5 = 28.
    private let e2e4 = ChessMove(from: 52, to: 36)

    func testMessageTextMatchesAndroid() {
        XCTAssertEqual(ChessWire.move(3, ChessMove(from: 52, to: 36)), "3:MOVE:52:36:0")
        XCTAssertEqual(ChessWire.move(0, ChessMove(from: 8, to: 0, promo: Chess.queen)), "0:MOVE:8:0:5")
        XCTAssertEqual(ChessWire.resign(2), "2:RESIGN")
        XCTAssertEqual(ChessWire.reset(5), "5:RESET")
    }

    func testMoveRoundTrips() {
        let m = ChessMove(from: 8, to: 0, promo: Chess.knight)
        XCTAssertEqual(ChessWire.parse(ChessWire.move(3, m)), ChessWireMessage.move(round: 3, move: m))
    }

    func testResignAndResetRoundTrip() {
        XCTAssertEqual(ChessWire.parse(ChessWire.resign(2)), ChessWireMessage.resign(round: 2))
        XCTAssertEqual(ChessWire.parse(ChessWire.reset(5)), ChessWireMessage.reset(round: 5))
    }

    func testMalformedMessagesAreRejected() {
        let bad = [
            "", "MOVE:52:36:0", "x:MOVE:52:36:0", "-1:MOVE:52:36:0",
            "0:MOVE:52:36", "0:MOVE:52:36:0:9", "0:MOVE:a:36:0",
            "0:MOVE:64:36:0", "0:MOVE:-1:36:0", "0:MOVE:52:64:0",
            "0:MOVE:52:36:1", "0:MOVE:52:36:6", "0:MOVE:52:36:7", "0:MOVE:52:36:-2",
            "0:MOVE:52:36:0 ", "0:RESIGN:1", "0:RESET:1", "0:HELLO:5", "0:", "0"
        ]
        for raw in bad {
            XCTAssertNil(ChessWire.parse(raw), "should reject '\(raw)'")
        }
    }

    func testLegalMoveIsAccepted() {
        XCTAssertEqual(ChessWire.validate(ChessPosition.start(), e2e4), e2e4)
    }

    func testIllegalMovesAreRefused() {
        let pos = ChessPosition.start()
        // Pawn three squares, a rook through its own pawn, an empty square,
        // the opponent's pawn, a diagonal pawn step with no capture, a
        // pointless promotion, and a king that stays where it is.
        let illegal = [
            ChessMove(from: 52, to: 20), ChessMove(from: 56, to: 40), ChessMove(from: 36, to: 28),
            ChessMove(from: 12, to: 28), ChessMove(from: 52, to: 43),
            ChessMove(from: 52, to: 36, promo: Chess.queen), ChessMove(from: 60, to: 60)
        ]
        for m in illegal {
            XCTAssertNil(ChessWire.validate(pos, m), "should refuse \(m)")
        }
    }

    func testCannotMoveTheWrongColour() {
        // White to move: Black's e7-e5 is not allowed.
        XCTAssertNil(ChessWire.validate(ChessPosition.start(), ChessMove(from: 12, to: 28)))
    }

    func testMovesThatLeaveTheKingInCheckAreRefused() {
        // The white bishop on e2 is pinned to its king on e1 by the rook on e8.
        let pos = ChessPosition.fromFen("4r2k/8/8/8/8/8/4B3/4K3 w - - 0 1")
        XCTAssertNil(ChessWire.validate(pos, ChessMove(from: 52, to: 45))) // Be2-f3 exposes the king
        XCTAssertTrue(ChessRules.legalMoves(pos).filter { $0.from == 52 }.isEmpty)
    }

    func testPromotionMustNameARealPromotion() {
        let pos = ChessPosition.fromFen("7k/P7/8/8/8/8/8/K7 w - - 0 1")
        XCTAssertNil(ChessWire.validate(pos, ChessMove(from: 8, to: 0)))                       // no piece named
        XCTAssertNotNil(ChessWire.validate(pos, ChessMove(from: 8, to: 0, promo: Chess.knight)))
        XCTAssertNil(ChessWire.validate(pos, ChessMove(from: 8, to: 0, promo: Chess.king)))     // can't become a king
    }

    func testCastlingAndEnPassantAreAccepted() {
        let castle = ChessPosition.fromFen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        XCTAssertNotNil(ChessWire.validate(castle, ChessMove(from: 60, to: 62)))
        // Castling through an attacked square (the rook on f2 covers f1) is refused.
        let attacked = ChessPosition.fromFen("r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1")
        XCTAssertNil(ChessWire.validate(attacked, ChessMove(from: 60, to: 62)))
        let ep = ChessPosition.fromFen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        XCTAssertNotNil(ChessWire.validate(ep, ChessMove(from: 28, to: 19)))
    }

    func testSeatsAlternateColourEachRound() {
        XCTAssertEqual(ChessWire.whiteSeat(0), 0)
        XCTAssertEqual(ChessWire.whiteSeat(1), 1)
        XCTAssertEqual(ChessWire.whiteSeat(2), 0)
    }

    func testSeatToMoveFollowsTheBoardAndRound() {
        let start = ChessPosition.start()
        XCTAssertEqual(ChessWire.seatToMove(start, round: 0), 0)
        XCTAssertEqual(ChessWire.seatToMove(start, round: 1), 1)
        let afterOne = ChessRules.apply(start, e2e4)
        XCTAssertEqual(ChessWire.seatToMove(afterOne, round: 0), 1)
        XCTAssertEqual(ChessWire.seatToMove(afterOne, round: 1), 0)
    }

    func testResetRoundsOnlyJumpForwardABit() {
        XCTAssertTrue(ChessWire.acceptableResetRound(current: 0, received: 1))
        XCTAssertTrue(ChessWire.acceptableResetRound(current: 0, received: 3))
        XCTAssertFalse(ChessWire.acceptableResetRound(current: 0, received: 0))
        XCTAssertFalse(ChessWire.acceptableResetRound(current: 4, received: 2))
        XCTAssertFalse(ChessWire.acceptableResetRound(current: 0, received: 4))
        XCTAssertFalse(ChessWire.acceptableResetRound(current: 0, received: Int.max))
    }

    func testOnlineIsOfferedForChessButStaysTwoPlayer() {
        XCTAssertTrue(GameCatalog.realMultiplayerGames.contains("CHESS"))
        XCTAssertFalse(GameCatalog.multiSeatMultiplayerGames.contains("CHESS"))
    }

    func testAWholeGameReplaysThroughTheWireIdentically() {
        // Fool's mate sent as text and rebuilt on the "other phone".
        let moves = [
            ChessMove(from: 53, to: 45), ChessMove(from: 12, to: 28),
            ChessMove(from: 54, to: 38), ChessMove(from: 3, to: 39)
        ]
        var mine = ChessPosition.start()
        var theirs = ChessPosition.start()
        for m in moves {
            let raw = ChessWire.move(0, m)
            mine = ChessRules.apply(mine, m)
            guard case .move(_, let received)? = ChessWire.parse(raw) else {
                XCTFail("did not parse \(raw)")
                return
            }
            guard let legal = ChessWire.validate(theirs, received) else {
                XCTFail("rejected \(raw)")
                return
            }
            theirs = ChessRules.apply(theirs, legal)
        }
        XCTAssertEqual(mine.key(), theirs.key())
        XCTAssertEqual(ChessRules.status(theirs), .checkmate)
    }
}
