import XCTest

/// Rules, bot and online messages of checkers - the same cases as Android's CheckersEngineTest and CheckersWireTest.
final class CheckersTests: XCTestCase {
    private func sq(_ r: Int, _ c: Int) -> Int { Checkers.square(r, c) }

    private func pos(redToMove: Bool, _ pieces: [(Int, Int, Int)]) -> CheckersPosition {
        var b = [Int](repeating: 0, count: 64)
        for (r, c, p) in pieces { b[sq(r, c)] = p }
        return CheckersPosition(board: b, redToMove: redToMove)
    }

    private func perft(_ p: CheckersPosition, _ depth: Int) -> Int {
        if depth == 0 { return 1 }
        return CheckersRules.legalMoves(p).reduce(0) { $0 + perft(CheckersRules.apply(p, $1), depth - 1) }
    }

    // MARK: Move generation

    func testStartingPositionHas12PiecesEachOnDarkSquares() {
        let p = CheckersPosition()
        XCTAssertEqual(CheckersRules.count(p, red: true), 12)
        XCTAssertEqual(CheckersRules.count(p, red: false), 12)
        for s in 0..<64 where p.board[s] != 0 { XCTAssertTrue(Checkers.isDark(s)) }
    }

    func testPublishedMoveCountsFromTheStartingPosition() {
        let expected = [7, 49, 302, 1469, 7361, 36768]
        for (i, n) in expected.enumerated() { XCTAssertEqual(perft(CheckersPosition(), i + 1), n, "depth \(i + 1)") }
    }

    func testMenStepForwardOnly() {
        let p = pos(redToMove: true, [(4, 3, Checkers.redMan)])
        XCTAssertEqual(Set(CheckersRules.legalMoves(p).map { $0.to }), [sq(3, 2), sq(3, 4)])
    }

    func testKingsStepInAllFourDirections() {
        XCTAssertEqual(CheckersRules.legalMoves(pos(redToMove: true, [(4, 3, Checkers.redKing)])).count, 4)
    }

    func testCapturingIsCompulsory() {
        let p = pos(redToMove: true, [(4, 3, Checkers.redMan), (3, 4, Checkers.blackMan), (7, 0, Checkers.redMan)])
        let moves = CheckersRules.legalMoves(p)
        XCTAssertEqual(moves.count, 1)
        XCTAssertTrue(moves[0].isCapture)
        XCTAssertEqual(moves[0].captured(), [sq(3, 4)])
    }

    func testMustContinueJumpingWithTheSamePiece() {
        let p = pos(redToMove: true, [(6, 1, Checkers.redMan), (5, 2, Checkers.blackMan), (3, 4, Checkers.blackMan)])
        let moves = CheckersRules.legalMoves(p)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].path, [sq(6, 1), sq(4, 3), sq(2, 5)])
        XCTAssertEqual(moves[0].captured().count, 2)
        XCTAssertEqual(CheckersRules.count(CheckersRules.apply(p, moves[0]), red: false), 0)
    }

    func testCannotJumpOwnPieceOrIntoOccupiedSquare() {
        let own = pos(redToMove: true, [(4, 3, Checkers.redMan), (3, 4, Checkers.redMan)])
        XCTAssertFalse(CheckersRules.legalMoves(own).contains { $0.isCapture })
        let blocked = pos(redToMove: true, [(4, 3, Checkers.redMan), (3, 4, Checkers.blackMan), (2, 5, Checkers.blackMan)])
        XCTAssertFalse(CheckersRules.legalMoves(blocked).contains { $0.isCapture })
    }

    func testAPieceCannotBeJumpedTwiceInOneMove() {
        let p = pos(redToMove: true, [(4, 3, Checkers.redKing), (3, 4, Checkers.blackMan), (5, 4, Checkers.blackMan), (3, 2, Checkers.blackMan)])
        for m in CheckersRules.legalMoves(p) { XCTAssertEqual(m.captured().count, Set(m.captured()).count) }
    }

    // MARK: Crowning

    func testManReachingTheFarRowIsCrowned() {
        let p = pos(redToMove: true, [(1, 2, Checkers.redMan), (7, 0, Checkers.blackMan)])
        let move = CheckersRules.legalMoves(p).first { $0.to == sq(0, 1) }!
        XCTAssertEqual(CheckersRules.apply(p, move).board[sq(0, 1)], Checkers.redKing)
    }

    func testAJumpThatCrownsEndsTheMove() {
        let p = pos(redToMove: true, [(2, 3, Checkers.redMan), (1, 2, Checkers.blackMan), (1, 4, Checkers.blackMan), (7, 6, Checkers.blackMan)])
        let crowning = CheckersRules.legalMoves(p).filter { $0.to == sq(0, 1) }
        XCTAssertFalse(crowning.isEmpty)
        XCTAssertTrue(crowning.allSatisfy { $0.path.count == 2 })
        XCTAssertEqual(CheckersRules.apply(p, crowning[0]).board[sq(0, 1)], Checkers.redKing)
    }

    func testBlackIsCrownedOnRow7() {
        let p = pos(redToMove: false, [(6, 1, Checkers.blackMan), (0, 1, Checkers.redMan)])
        let move = CheckersRules.legalMoves(p).first { $0.to == sq(7, 0) }!
        XCTAssertEqual(CheckersRules.apply(p, move).board[sq(7, 0)], Checkers.blackKing)
    }

    // MARK: Results

    func testSideWithNoMovesLoses() {
        XCTAssertEqual(CheckersRules.result(pos(redToMove: false, [(4, 3, Checkers.redMan)])), .redWins)
        let blocked = pos(redToMove: false, [(7, 0, Checkers.blackKing), (6, 1, Checkers.redMan), (5, 2, Checkers.redMan)])
        XCTAssertEqual(CheckersRules.result(blocked), .redWins)
    }

    func testNewGameIsOngoing() {
        XCTAssertEqual(CheckersRules.result(CheckersPosition()), .ongoing)
    }

    func testQuietKingMovesAreDrawnAfter80Plies() {
        var p = pos(redToMove: true, [(7, 0, Checkers.redKing), (0, 7, Checkers.blackKing)])
        p.quietPlies = Checkers.drawPlies - 1
        p = CheckersRules.apply(p, CheckersRules.legalMoves(p)[0])
        XCTAssertEqual(CheckersRules.result(p), .draw)
    }

    func testManMovesAndCapturesResetTheDrawCounter() {
        var p = pos(redToMove: true, [(4, 3, Checkers.redMan), (0, 7, Checkers.blackKing)])
        p.quietPlies = 50
        XCTAssertEqual(CheckersRules.apply(p, CheckersRules.legalMoves(p)[0]).quietPlies, 0)
    }

    func testThreefoldRepetitionIsADraw() {
        XCTAssertEqual(CheckersRules.result(CheckersPosition(), repeats: 3), .draw)
        XCTAssertEqual(CheckersRules.result(CheckersPosition(), repeats: 2), .ongoing)
    }

    func testPositionKeyDiffersBySideToMove() {
        XCTAssertNotEqual(CheckersPosition().key(), CheckersPosition(redToMove: false).key())
    }

    // MARK: Wire and validation

    func testMovesRoundTripThroughTheWireFormat() {
        let m = CheckersMove(path: [sq(6, 1), sq(4, 3), sq(2, 5)])
        XCTAssertEqual(CheckersMove.fromWire(m.toWire()), m)
    }

    func testMalformedWireMovesAreRejected() {
        for bad in ["", "12", "a-b", "12-99", "0-9", "-1-5"] { XCTAssertNil(CheckersMove.fromWire(bad), bad) }
    }

    func testValidateOnlyAcceptsLegalMoves() {
        let p = CheckersPosition()
        let legal = CheckersRules.legalMoves(p)[0]
        XCTAssertNotNil(CheckersRules.validate(p, CheckersMove(path: legal.path)))
        XCTAssertNil(CheckersRules.validate(p, CheckersMove(path: [sq(5, 0), sq(2, 3)])))
    }

    func testEveryMessageRoundTrips() {
        let move = CheckersMove(path: [42, 33, 24])
        XCTAssertEqual(CheckersWire.parse(CheckersWire.move(3, move)), .move(round: 3, move: move))
        XCTAssertEqual(CheckersWire.parse(CheckersWire.resign(0)), .resign(round: 0))
        XCTAssertEqual(CheckersWire.parse(CheckersWire.reset(4)), .reset(round: 4))
        XCTAssertEqual(CheckersWire.parse(CheckersWire.newGameOffer(1)), .newGameOffer(round: 1))
        XCTAssertEqual(CheckersWire.parse(CheckersWire.newGameDecline(1)), .newGameDecline(round: 1))
        XCTAssertEqual(CheckersWire.parse(CheckersWire.drawOffer(2)), .drawOffer(round: 2))
        XCTAssertEqual(CheckersWire.parse(CheckersWire.drawAccept(2)), .drawAccept(round: 2))
        XCTAssertEqual(CheckersWire.parse(CheckersWire.drawDecline(2)), .drawDecline(round: 2))
    }

    func testMoveWireTextLooksAsDocumented() {
        XCTAssertEqual(CheckersWire.move(3, CheckersMove(path: [42, 33, 24])), "3:MOVE:42-33-24")
    }

    func testMalformedMessagesAreRejected() {
        for bad in ["", "x", "1", "-1:RESIGN", "a:RESIGN", "1:RESIGN:extra", "1:MOVE", "1:MOVE:", "1:MOVE:5", "1:MOVE:0-9",
                    "1:MOVE:42-99", "1:MOVE:42-33:extra", "1:BOGUS", "1:DRAW:1"] {
            XCTAssertNil(CheckersWire.parse(bad), "should reject '\(bad)'")
        }
    }

    func testHostIsRedInRoundZeroAndTheColoursSwapEachRound() {
        XCTAssertEqual(CheckersWire.redSeat(0), 0)
        XCTAssertEqual(CheckersWire.redSeat(1), 1)
        XCTAssertEqual(CheckersWire.redSeat(2), 0)
    }

    func testSeatToMoveFollowsTheSideToMove() {
        let start = CheckersPosition()
        XCTAssertEqual(CheckersWire.seatToMove(start, round: 0), 0)
        XCTAssertEqual(CheckersWire.seatToMove(start, round: 1), 1)
        let afterOne = CheckersRules.apply(start, CheckersRules.legalMoves(start)[0])
        XCTAssertEqual(CheckersWire.seatToMove(afterOne, round: 0), 1)
    }

    func testOnlyASmallStepForwardResetsTheRound() {
        XCTAssertTrue(CheckersWire.acceptableResetRound(current: 2, received: 3))
        XCTAssertTrue(CheckersWire.acceptableResetRound(current: 2, received: 5))
        XCTAssertFalse(CheckersWire.acceptableResetRound(current: 2, received: 2))
        XCTAssertFalse(CheckersWire.acceptableResetRound(current: 2, received: 6))
    }

    // MARK: Bot

    func testBotReturnsALegalMoveAtEveryDifficulty() {
        for d in ["EASY", "MEDIUM", "HARD"] {
            let p = CheckersPosition()
            let m = CheckersBot.chooseMove(p, difficulty: d, seed: 1)!
            XCTAssertNotNil(CheckersRules.validate(p, m))
        }
    }

    func testBotTakesAFreePieceWhenItCanAtMediumAndHard() {
        let p = pos(redToMove: false, [(3, 2, Checkers.blackMan), (4, 3, Checkers.redMan), (0, 1, Checkers.blackMan)])
        for d in ["MEDIUM", "HARD"] { XCTAssertTrue(CheckersBot.chooseMove(p, difficulty: d, seed: 2)!.isCapture) }
    }

    func testBotFindsTheWinningDoubleJump() {
        let p = pos(redToMove: false, [(1, 2, Checkers.blackMan), (2, 3, Checkers.redMan), (4, 5, Checkers.redMan), (0, 7, Checkers.blackMan)])
        XCTAssertEqual(CheckersBot.chooseMove(p, difficulty: "HARD", seed: 3)!.captured().count, 2)
    }

    func testBotPlaysAWholeGameWithoutIllegalMoves() {
        var p = CheckersPosition()
        var seen: [String: Int] = [:]
        var plies = 0
        while plies < 400 {
            seen[p.key(), default: 0] += 1
            if CheckersRules.result(p, repeats: seen[p.key()]!) != .ongoing { break }
            let m = CheckersBot.chooseMove(p, difficulty: "EASY", seed: UInt64(plies))!
            XCTAssertNotNil(CheckersRules.validate(p, m))
            p = CheckersRules.apply(p, m)
            plies += 1
        }
        XCTAssertGreaterThan(plies, 4)
    }
}
