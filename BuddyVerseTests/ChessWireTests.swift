import XCTest

/// Mirrors Android's ChessWireTest: the online chess message format, the clock,
/// and that the iPhone and Android sides read each other's messages the same way.
final class ChessWireTests: XCTestCase {
    func testMoveRoundTrips() {
        let m = ChessMove(from: 52, to: 36)
        XCTAssertEqual(ChessWire.parse(ChessWire.move(0, m)), .move(round: 0, move: m))
        XCTAssertEqual(ChessWire.move(3, ChessMove(from: 8, to: 0, promo: 5)), "3:MOVE:8:0:5")
    }

    func testMalformedMovesAreRejected() {
        XCTAssertNil(ChessWire.parse("0:MOVE:64:0:0"))
        XCTAssertNil(ChessWire.parse("0:MOVE:0:0:1"))   // 1 = pawn, not a promotion piece
        XCTAssertNil(ChessWire.parse("0:MOVE:0:0"))
        XCTAssertNil(ChessWire.parse("-1:RESIGN"))
        XCTAssertNil(ChessWire.parse("nonsense"))
    }

    func testClockMessageOnlyAllowsTheLobbyChoices() {
        for seconds in [0, 180, 300, 600] {
            XCTAssertEqual(ChessWire.parse(ChessWire.clock(0, seconds)), .clock(round: 0, seconds: seconds))
        }
        XCTAssertNil(ChessWire.parse("0:CLOCK:1"))
        XCTAssertNil(ChessWire.parse("0:CLOCK:-300"))
        XCTAssertNil(ChessWire.parse("0:CLOCK"))
        XCTAssertNil(ChessWire.parse("0:CLOCK:300:extra"))
        XCTAssertNil(ChessWire.parse("0:CLOCK:abc"))
    }

    func testTimeoutDrawNewGameAndTakebackRoundTrip() {
        XCTAssertEqual(ChessWire.parse(ChessWire.timeout(2)), .timeout(round: 2))
        XCTAssertEqual(ChessWire.parse(ChessWire.drawOffer(1)), .drawOffer(round: 1))
        XCTAssertEqual(ChessWire.parse(ChessWire.drawAccept(1)), .drawAccept(round: 1))
        XCTAssertEqual(ChessWire.parse(ChessWire.drawDecline(1)), .drawDecline(round: 1))
        XCTAssertEqual(ChessWire.parse(ChessWire.newGameOffer(3)), .newGameOffer(round: 3))
        XCTAssertEqual(ChessWire.parse(ChessWire.newGameDecline(3)), .newGameDecline(round: 3))
        XCTAssertEqual(ChessWire.parse(ChessWire.takeback(0, 7)), .takebackRequest(round: 0, ply: 7))
        XCTAssertEqual(ChessWire.parse(ChessWire.takebackAccept(0, 7)), .takebackAccept(round: 0, ply: 7))
        XCTAssertEqual(ChessWire.parse(ChessWire.takebackDecline(0, 7)), .takebackDecline(round: 0, ply: 7))
    }

    func testMalformedDrawAndTakebackMessagesAreRejected() {
        XCTAssertNil(ChessWire.parse("0:DRAW:1"))
        XCTAssertNil(ChessWire.parse("0:DRAWOK:1"))
        XCTAssertNil(ChessWire.parse("0:TIMEOUT:5"))
        XCTAssertNil(ChessWire.parse("3:NEWGAME:1"))
        XCTAssertNil(ChessWire.parse("0:TAKEBACK"))
        XCTAssertNil(ChessWire.parse("0:TAKEBACK:0"))
        XCTAssertNil(ChessWire.parse("0:TAKEBACK:-3"))
        XCTAssertNil(ChessWire.parse("0:TBOK:\(ChessWire.maxPly + 1)"))
        XCTAssertNil(ChessWire.parse("0:TBNO:x"))
        XCTAssertNil(ChessWire.parse("0:TBOK:1:2"))
    }

    func testClockStaysStillUntilTheFirstMove() {
        let c = ChessClock(totalMs: 300_000)
        XCTAssertEqual(c.remaining(white: true, now: 0), 300_000)
        XCTAssertEqual(c.remaining(white: true, now: 50_000), 300_000)
        XCTAssertEqual(c.remaining(white: false, now: 50_000), 300_000)
    }

    func testClockChargesOnlyTheSideToMoveAndHandsOverOnEachMove() {
        let c = ChessClock(totalMs: 300_000)
        c.switchTo(false, now: 1_000)                        // White moved; Black's clock starts
        XCTAssertEqual(c.remaining(white: true, now: 11_000), 300_000)
        XCTAssertEqual(c.remaining(white: false, now: 11_000), 290_000)
        c.switchTo(true, now: 11_000)                        // Black moved; White's clock starts
        XCTAssertEqual(c.remaining(white: false, now: 40_000), 290_000)
        XCTAssertEqual(c.remaining(white: true, now: 16_000), 295_000)
    }

    func testClockCanGoBelowZeroAndStopFreezesEverything() {
        let c = ChessClock(totalMs: 10_000)
        c.switchTo(true, now: 0)
        XCTAssertEqual(c.remaining(white: true, now: 12_000), -2_000)
        c.stop(now: 12_000)
        XCTAssertEqual(c.remaining(white: true, now: 99_000), -2_000)
        XCTAssertEqual(c.remaining(white: false, now: 99_000), 10_000)
    }

    func testWhiteSeatSwapsEveryRoundLikeAndroid() {
        XCTAssertEqual(ChessWire.whiteSeat(0), 0)
        XCTAssertEqual(ChessWire.whiteSeat(1), 1)
        XCTAssertEqual(ChessWire.whiteSeat(2), 0)
        XCTAssertTrue(ChessWire.acceptableResetRound(current: 1, received: 2))
        XCTAssertFalse(ChessWire.acceptableResetRound(current: 1, received: 1))
        XCTAssertFalse(ChessWire.acceptableResetRound(current: 1, received: 9))
    }
}
