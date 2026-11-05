import XCTest

/// Swift twin of Android's ChessEngineTest (same positions, same expected
/// numbers). "Perft" counts how many move sequences of a given length exist
/// from a position; the totals are the well-known published values, so if the
/// move generator gets any rule wrong (castling, en passant, promotion, pins)
/// one of them will be off. This test target compiles ChessEngine.swift
/// directly (see project.yml), so it needs no app launch and no Firebase.
final class ChessEngineTests: XCTestCase {

    // MARK: - helpers

    private func perft(_ pos: ChessPosition, _ depth: Int) -> Int {
        if depth == 0 { return 1 }
        var total = 0
        for m in ChessRules.legalMoves(pos) { total += perft(ChessRules.apply(pos, m), depth - 1) }
        return total
    }

    private func check(_ fen: String, _ expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        let pos = ChessPosition.fromFen(fen)
        for (i, e) in expected.enumerated() {
            XCTAssertEqual(perft(pos, i + 1), e, "\(fen) depth \(i + 1)", file: file, line: line)
        }
    }

    /// "e4" -> board index (a8 = 0, h1 = 63).
    private func sq(_ name: String) -> Int {
        let chars = Array(name)
        return (8 - chars[1].wholeNumberValue!) * 8 + Int(chars[0].asciiValue! - 97)
    }

    private func mv(_ from: String, _ to: String, _ promo: Int = 0) -> ChessMove {
        ChessMove(from: sq(from), to: sq(to), promo: promo)
    }

    private func fen(_ text: String) -> ChessPosition { ChessPosition.fromFen(text) }

    private func legal(_ pos: ChessPosition, _ from: String, _ to: String) -> [ChessMove] {
        ChessRules.legalMoves(pos).filter { $0.from == sq(from) && $0.to == sq(to) }
    }

    private func play(_ pos: ChessPosition, _ moves: [(String, String)]) -> ChessPosition {
        var p = pos
        for (a, b) in moves {
            let found = legal(p, a, b)
            XCTAssertFalse(found.isEmpty, "\(a)\(b) should be legal")
            guard let move = found.first else { return p }
            p = ChessRules.apply(p, move)
        }
        return p
    }

    // MARK: - published perft totals

    func testStartPosition() { check(Chess.startFen, [20, 400, 8902, 197281]) }

    func testKiwipete() {
        check("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862])
    }

    func testEnPassantAndPins() { check("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43238]) }

    func testPromotionsAndCastlingRights() {
        check("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467])
    }

    func testMixedPosition() {
        check("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62379])
    }

    func testPerftPosition6() {
        check("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", [46, 2079, 89890])
    }

    // MARK: - reading FEN

    func testFenSetsUpTheStartBoard() {
        let pos = ChessPosition.start()
        XCTAssertEqual(pos.board[sq("a8")], -Chess.rook)
        XCTAssertEqual(pos.board[sq("e1")], Chess.king)
        XCTAssertEqual(pos.board[sq("e8")], -Chess.king)
        XCTAssertEqual(pos.board[sq("h2")], Chess.pawn)
        XCTAssertEqual(pos.board[sq("e4")], 0)
        XCTAssertTrue(pos.whiteToMove)
        XCTAssertEqual(pos.castle, 15)
        XCTAssertEqual(pos.ep, -1)
    }

    func testFenReadsEnPassantSquareAndHalfmove() {
        let pos = fen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b Kq e3 7 1")
        XCTAssertEqual(pos.ep, sq("e3"))
        XCTAssertEqual(pos.halfmove, 7)
        XCTAssertFalse(pos.whiteToMove)
        XCTAssertEqual(pos.castle, Chess.castleWK | Chess.castleBQ)
    }

    func testFenWithJunkDoesNotCrash() {
        let pos = fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNRXXXX w - zz x")
        XCTAssertEqual(pos.ep, -1)
        XCTAssertEqual(pos.halfmove, 0)
    }

    // MARK: - repetition keys

    func testKnightShuffleReturnsToTheSameKey() {
        let start = ChessPosition.start()
        let back = play(start, [("g1", "f3"), ("g8", "f6"), ("f3", "g1"), ("f6", "g8")])
        XCTAssertEqual(start.key(), back.key())
    }

    func testKeyDiffersByWhoIsToMove() {
        XCTAssertNotEqual(fen("4k3/8/8/8/8/8/8/4K3 w - - 0 1").key(), fen("4k3/8/8/8/8/8/8/4K3 b - - 0 1").key())
    }

    func testKeyDiffersByCastlingRights() {
        XCTAssertNotEqual(fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1").key(),
                          fen("r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1").key())
    }

    func testUnusableEnPassantSquareDoesNotChangeTheKey() {
        // After e4 nobody can capture en passant, so this equals the same board with no ep square.
        let afterE4 = play(ChessPosition.start(), [("e2", "e4")])
        let same = fen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
        XCTAssertEqual(same.key(), afterE4.key())
    }

    func testUsableEnPassantSquareChangesTheKey() {
        XCTAssertNotEqual(fen("4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1").key(),
                          fen("4k3/8/8/8/3pP3/8/8/4K3 b - - 0 1").key())
    }

    // MARK: - applying moves

    func testApplyLeavesTheOriginalPositionAlone() {
        let start = ChessPosition.start()
        let before = start.board
        _ = ChessRules.apply(start, mv("e2", "e4"))
        XCTAssertEqual(before, start.board)
        XCTAssertTrue(start.whiteToMove)
    }

    func testHalfmoveCounterResetsOnPawnMovesAndCaptures() {
        var pos = fen("4k3/8/8/3p4/8/8/3P4/4K1N1 w - - 5 1")
        pos = ChessRules.apply(pos, mv("g1", "f3"))
        XCTAssertEqual(pos.halfmove, 6)
        pos = ChessRules.apply(pos, mv("e8", "e7"))
        XCTAssertEqual(pos.halfmove, 7)
        pos = ChessRules.apply(pos, mv("d2", "d4"))
        XCTAssertEqual(pos.halfmove, 0)
        // A capture also resets it: the knight takes a pawn.
        let capture = ChessRules.apply(fen("4k3/8/8/4p3/8/5N2/8/4K3 w - - 7 1"), mv("f3", "e5"))
        XCTAssertEqual(capture.halfmove, 0)
    }

    func testDoubleStepSetsEnPassantSquareForOneMoveOnly() {
        var pos = play(ChessPosition.start(), [("e2", "e4")])
        XCTAssertEqual(pos.ep, sq("e3"))
        pos = play(pos, [("g8", "f6")])
        XCTAssertEqual(pos.ep, -1)
    }

    // MARK: - en passant

    func testEnPassantRemovesTheCapturedPawn() {
        let after = ChessRules.apply(fen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1"), mv("e5", "d6"))
        XCTAssertEqual(after.board[sq("d6")], Chess.pawn)
        XCTAssertEqual(after.board[sq("d5")], 0)
        XCTAssertEqual(after.board[sq("e5")], 0)
    }

    func testBlackCanCaptureEnPassantToo() {
        let after = ChessRules.apply(fen("4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1"), mv("d4", "e3"))
        XCTAssertEqual(after.board[sq("e3")], -Chess.pawn)
        XCTAssertEqual(after.board[sq("e4")], 0)
    }

    func testEnPassantThatExposesTheKingIsIllegal() {
        // Taking en passant would remove both pawns from the fifth rank and open the rook's line to the king.
        let pos = fen("8/8/8/K2pP2r/8/8/8/7k w - d6 0 1")
        XCTAssertTrue(legal(pos, "e5", "d6").isEmpty)
        XCTAssertFalse(legal(pos, "e5", "e6").isEmpty)
    }

    // MARK: - castling

    func testBothSidesCanCastleBothWaysWhenClear() {
        let white = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        XCTAssertFalse(legal(white, "e1", "g1").isEmpty)
        XCTAssertFalse(legal(white, "e1", "c1").isEmpty)
        let black = fen("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
        XCTAssertFalse(legal(black, "e8", "g8").isEmpty)
        XCTAssertFalse(legal(black, "e8", "c8").isEmpty)
    }

    func testCastlingMovesTheRookToo() {
        let pos = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let short = ChessRules.apply(pos, mv("e1", "g1"))
        XCTAssertEqual(short.board[sq("g1")], Chess.king)
        XCTAssertEqual(short.board[sq("f1")], Chess.rook)
        XCTAssertEqual(short.board[sq("h1")], 0)
        let long = ChessRules.apply(pos, mv("e1", "c1"))
        XCTAssertEqual(long.board[sq("c1")], Chess.king)
        XCTAssertEqual(long.board[sq("d1")], Chess.rook)
        XCTAssertEqual(long.board[sq("a1")], 0)
        XCTAssertEqual(long.castle, Chess.castleBK | Chess.castleBQ)
    }

    func testCannotCastleOutOfCheck() {
        let pos = fen("4k3/8/8/8/8/8/4r3/R3K2R w KQ - 0 1")
        XCTAssertTrue(legal(pos, "e1", "g1").isEmpty)
        XCTAssertTrue(legal(pos, "e1", "c1").isEmpty)
    }

    func testCannotCastleThroughAnAttackedSquare() {
        // The black rook on f8 attacks f1, which the king would cross.
        let pos = fen("4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        XCTAssertTrue(legal(pos, "e1", "g1").isEmpty)
        XCTAssertFalse(legal(pos, "e1", "c1").isEmpty)
    }

    func testCannotCastleIntoCheck() {
        XCTAssertTrue(legal(fen("4k1r1/8/8/8/8/8/8/R3K2R w KQ - 0 1"), "e1", "g1").isEmpty)
    }

    func testLongCastleAllowedWhenOnlyTheRookCrossesAnAttackedSquare() {
        // b1 is attacked but only the rook passes over it, which is allowed.
        XCTAssertFalse(legal(fen("1r2k3/8/8/8/8/8/8/R3K3 w Q - 0 1"), "e1", "c1").isEmpty)
    }

    func testCannotCastleThroughAPiece() {
        let pos = fen("r3k2r/8/8/8/8/8/8/RN2K1NR w KQkq - 0 1")
        XCTAssertTrue(legal(pos, "e1", "g1").isEmpty)
        XCTAssertTrue(legal(pos, "e1", "c1").isEmpty)
    }

    func testMovingKingOrRookLosesTheRight() {
        let pos = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        XCTAssertEqual(ChessRules.apply(pos, mv("e1", "e2")).castle, Chess.castleBK | Chess.castleBQ)
        XCTAssertEqual(ChessRules.apply(pos, mv("a1", "a2")).castle, Chess.castleWK | Chess.castleBK | Chess.castleBQ)
        XCTAssertEqual(ChessRules.apply(pos, mv("h1", "h2")).castle, Chess.castleWQ | Chess.castleBK | Chess.castleBQ)
    }

    func testCapturingARookInItsCornerRemovesThatRight() {
        let after = ChessRules.apply(fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"), mv("a1", "a8"))
        XCTAssertEqual(after.castle & Chess.castleBQ, 0)
        XCTAssertEqual(after.castle & Chess.castleWQ, 0)
        XCTAssertNotEqual(after.castle & Chess.castleBK, 0)
    }

    // MARK: - promotion

    func testPromotionOffersFourPieces() {
        let moves = legal(fen("8/P6k/8/8/8/8/8/K7 w - - 0 1"), "a7", "a8")
        XCTAssertEqual(Set(moves.map { $0.promo }), [Chess.queen, Chess.rook, Chess.bishop, Chess.knight])
        XCTAssertEqual(moves.count, 4)
    }

    func testPromotionPlacesAPieceOfTheRightColour() {
        let white = ChessRules.apply(fen("8/P6k/8/8/8/8/8/K7 w - - 0 1"), mv("a7", "a8", Chess.knight))
        XCTAssertEqual(white.board[sq("a8")], Chess.knight)
        let black = ChessRules.apply(fen("k7/8/8/8/8/8/p6K/8 b - - 0 1"), mv("a2", "a1", Chess.queen))
        XCTAssertEqual(black.board[sq("a1")], -Chess.queen)
    }

    func testPawnCanPromoteByCapturing() {
        let pos = fen("1n5k/P7/8/8/8/8/8/K7 w - - 0 1")
        XCTAssertEqual(legal(pos, "a7", "b8").count, 4)
        XCTAssertFalse(legal(pos, "a7", "a8").isEmpty)
    }

    func testBlockedPawnCannotMoveOrDoubleStep() {
        let blocked = fen("4k3/8/8/8/8/4n3/4P3/4K3 w - - 0 1")
        XCTAssertTrue(ChessRules.legalMoves(blocked).allSatisfy { $0.from != sq("e2") })
        let open = fen("4k3/8/8/8/4n3/8/4P3/4K3 w - - 0 1")
        XCTAssertFalse(legal(open, "e2", "e3").isEmpty)
        XCTAssertTrue(legal(open, "e2", "e4").isEmpty)
    }

    // MARK: - check and pins

    func testPinnedPieceCannotLeaveTheLine() {
        let pos = fen("4r1k1/8/8/8/8/8/4B3/4K3 w - - 0 1")
        XCTAssertTrue(ChessRules.legalMoves(pos).allSatisfy { $0.from != sq("e2") })
    }

    func testInCheckOnlyEvasionsAreLegal() {
        let pos = fen("4k3/8/8/8/8/8/4r3/4K1N1 w - - 0 1")
        XCTAssertTrue(ChessRules.inCheck(pos, white: true))
        for m in ChessRules.legalMoves(pos) {
            XCTAssertFalse(ChessRules.inCheck(ChessRules.apply(pos, m), white: true))
        }
        XCTAssertFalse(legal(pos, "e1", "e2").isEmpty) // king takes the undefended rook
        XCTAssertFalse(legal(pos, "g1", "e2").isEmpty) // knight takes it
    }

    func testKingsCannotStandNextToEachOther() {
        let pos = fen("8/8/8/8/8/3k4/8/3K4 w - - 0 1")
        XCTAssertTrue(legal(pos, "d1", "d2").isEmpty)
        XCTAssertTrue(legal(pos, "d1", "c2").isEmpty)
        XCTAssertTrue(legal(pos, "d1", "e2").isEmpty)
        XCTAssertFalse(legal(pos, "d1", "c1").isEmpty)
    }

    // MARK: - game end

    func testFoolsMateIsCheckmate() {
        let pos = play(ChessPosition.start(), [("f2", "f3"), ("e7", "e5"), ("g2", "g4"), ("d8", "h4")])
        XCTAssertEqual(ChessRules.status(pos), .checkmate)
    }

    func testStalemateIsADraw() {
        XCTAssertEqual(ChessRules.status(fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")), .stalemate)
    }

    func testScholarsMateIsCheckmate() {
        let pos = play(ChessPosition.start(), [("e2", "e4"), ("e7", "e5"), ("d1", "h5"), ("b8", "c6"),
                                               ("f1", "c4"), ("g8", "f6"), ("h5", "f7")])
        XCTAssertEqual(ChessRules.status(pos), .checkmate)
    }

    func testBackRankMate() {
        let pos = fen("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1")
        XCTAssertEqual(ChessRules.status(ChessRules.apply(pos, mv("a1", "a8"))), .checkmate)
    }

    func testCheckIsNotMateWhenTheKingCanEscape() {
        let check = ChessRules.apply(fen("6k1/8/8/8/8/8/8/R3K3 w - - 0 1"), mv("a1", "a8"))
        XCTAssertTrue(ChessRules.inCheck(check, white: false))
        XCTAssertEqual(ChessRules.status(check), .ongoing)
    }

    func testFiftyMoveRuleDrawsAtOneHundredHalfMoves() {
        XCTAssertEqual(ChessRules.status(fen("4k3/8/8/8/8/8/R7/4K3 w - - 99 80")), .ongoing)
        XCTAssertEqual(ChessRules.status(fen("4k3/8/8/8/8/8/R7/4K3 w - - 100 80")), .drawFifty)
    }

    func testCheckmateBeatsTheFiftyMoveRule() {
        XCTAssertEqual(ChessRules.status(fen("R5k1/5ppp/8/8/8/8/8/4K3 b - - 100 80")), .checkmate)
    }

    func testQueenStalemateIsADrawNotAMate() {
        let pos = fen("k7/2Q5/1K6/8/8/8/8/8 b - - 0 1")
        XCTAssertFalse(ChessRules.inCheck(pos, white: false))
        XCTAssertEqual(ChessRules.status(pos), .stalemate)
    }

    func testInsufficientMaterialCases() {
        func draw(_ f: String) -> Bool { ChessRules.insufficientMaterial(fen(f).board) }
        XCTAssertTrue(draw("4k3/8/8/8/8/8/8/4K3 w - - 0 1"))
        XCTAssertTrue(draw("4k3/8/8/8/8/8/8/3BK3 w - - 0 1"))
        XCTAssertTrue(draw("4k3/8/8/8/8/8/8/3NK3 w - - 0 1"))
        // Bishops on the same colour of square (c1 and f8 are both dark) can never mate.
        XCTAssertTrue(draw("5b1k/8/8/8/8/8/8/2B1K3 w - - 0 1"))
        // Bishops on opposite colours can, with help.
        XCTAssertFalse(draw("4k3/8/8/8/8/8/8/2B1K2b w - - 0 1"))
        XCTAssertFalse(draw("4k3/8/8/8/8/8/8/2NNK3 w - - 0 1"))
        XCTAssertFalse(draw("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"))
        XCTAssertFalse(draw("4k3/8/8/8/8/8/8/R3K3 w - - 0 1"))
        XCTAssertFalse(draw("4k3/8/8/8/8/8/8/3QK3 w - - 0 1"))
    }

    func testStatusReportsInsufficientMaterial() {
        XCTAssertEqual(ChessRules.status(fen("4k3/8/8/8/8/8/8/3BK3 w - - 0 1")), .drawMaterial)
    }

    // MARK: - the computer opponent

    func testBotFindsMateInOne() {
        let pos = fen("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1")
        guard let move = ChessBot.choose(pos, difficulty: "MEDIUM") else { return XCTFail("no move") }
        XCTAssertEqual(ChessRules.status(ChessRules.apply(pos, move)), .checkmate)
    }

    func testBotHasNoMoveWhenTheGameIsOver() {
        let over = fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        XCTAssertNil(ChessBot.choose(over, difficulty: "HARD"))
        XCTAssertNil(ChessBot.choose(over, difficulty: "EASY"))
    }

    func testBotTakesAFreeQueen() {
        XCTAssertEqual(ChessBot.choose(fen("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1"), difficulty: "MEDIUM"), mv("d1", "d5"))
    }

    func testBotAsBlackFindsMateInOne() {
        let pos = fen("r3k3/8/8/8/8/8/5PPP/6K1 b - - 0 1")
        guard let move = ChessBot.choose(pos, difficulty: "MEDIUM") else { return XCTFail("no move") }
        XCTAssertEqual(ChessRules.status(ChessRules.apply(pos, move)), .checkmate)
    }

    func testBotPromotesInsteadOfWanderingOff() {
        let move = ChessBot.choose(fen("8/P6k/8/8/8/8/8/K7 w - - 0 1"), difficulty: "MEDIUM")
        XCTAssertEqual(move?.promo, Chess.queen)
    }

    func testEveryDifficultyAlwaysPlaysALegalMove() {
        for level in ["EASY", "MEDIUM"] {
            var pos = ChessPosition.start()
            for _ in 0..<6 {
                guard let move = ChessBot.choose(pos, difficulty: level) else { break }
                XCTAssertTrue(ChessRules.legalMoves(pos).contains(move), "\(level) played an illegal move")
                pos = ChessRules.apply(pos, move)
            }
        }
    }
}
