import XCTest

/// Mirrors ChessEngineTest.kt. "Perft" counts how many move sequences of a
/// given length exist from a position. The numbers below are the well-known
/// published values (and the same ones the Android test checks), so if the
/// move generator gets any rule wrong (castling, en passant, promotion, pins)
/// one of these totals will be off.
final class ChessEngineTests: XCTestCase {
    // Squares are numbered 0 = a8 ... 63 = h1: e2 = 52, e4 = 36.
    private let e2e4 = ChessMove(from: 52, to: 36)

    private func perft(_ pos: ChessPosition, _ depth: Int) -> Int {
        if depth == 0 { return 1 }
        var total = 0
        for m in ChessRules.legalMoves(pos) {
            total += perft(ChessRules.apply(pos, m), depth - 1)
        }
        return total
    }

    private func check(_ fen: String, _ expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        let pos = ChessPosition.fromFen(fen)
        for (i, e) in expected.enumerated() {
            XCTAssertEqual(perft(pos, i + 1), e, "\(fen) depth \(i + 1)", file: file, line: line)
        }
    }

    func testStartPosition() {
        check(Chess.startFen, [20, 400, 8902, 197281])
    }

    func testKiwipete() {
        check("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862])
    }

    func testEnPassantAndPins() {
        check("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43238])
    }

    func testPromotionsAndCastlingRights() {
        check("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467])
    }

    func testMixedPosition() {
        check("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62379])
    }

    // The FEN reader is the one part of the engine that is easy to get subtly
    // wrong in a port, so check the start position piece by piece.
    func testStartPositionIsReadCorrectly() {
        let pos = ChessPosition.start()
        XCTAssertEqual(pos.board[0], -Chess.rook)
        XCTAssertEqual(pos.board[4], -Chess.king)
        XCTAssertEqual(pos.board[8], -Chess.pawn)
        XCTAssertEqual(pos.board[59], Chess.queen)
        XCTAssertEqual(pos.board[60], Chess.king)
        XCTAssertEqual(pos.board[63], Chess.rook)
        XCTAssertEqual(pos.board.filter { $0 != 0 }.count, 32)
        XCTAssertTrue(pos.whiteToMove)
        XCTAssertEqual(pos.castle, Chess.castleWK | Chess.castleWQ | Chess.castleBK | Chess.castleBQ)
        XCTAssertEqual(pos.ep, -1)
        XCTAssertEqual(pos.halfmove, 0)
    }

    func testEnPassantSquareAndHalfmoveAreRead() {
        let pos = ChessPosition.fromFen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 7 30")
        XCTAssertEqual(pos.ep, 19) // d6 = row 2, column 3
        XCTAssertEqual(pos.halfmove, 7)
        XCTAssertEqual(pos.castle, 0)
        XCTAssertEqual(ChessPosition.fromFen("4k3/8/8/8/8/8/8/4K3 b - b3 0 1").ep, 41) // b3 = row 5, column 1
        XCTAssertFalse(ChessPosition.fromFen("4k3/8/8/8/8/8/8/4K3 b - - 0 1").whiteToMove)
    }

    func testFoolsMateIsCheckmate() {
        var pos = ChessPosition.start()
        // 1. f3 e5 2. g4 Qh4#
        for (from, to) in [(53, 45), (12, 28), (54, 38), (3, 39)] {
            pos = ChessRules.apply(pos, ChessMove(from: from, to: to))
        }
        XCTAssertEqual(ChessRules.status(pos), .checkmate)
    }

    func testStalemateIsADraw() {
        let pos = ChessPosition.fromFen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        XCTAssertEqual(ChessRules.status(pos), .stalemate)
    }

    func testAutomaticDraws() {
        // King against king can never win.
        XCTAssertEqual(ChessRules.status(ChessPosition.fromFen("4k3/8/8/8/8/8/8/4K3 w - - 0 1")), .drawMaterial)
        // A hundred half-moves with no capture or pawn move.
        XCTAssertEqual(ChessRules.status(ChessPosition.fromFen("4k3/8/8/8/8/8/8/R3K3 w - - 100 80")), .drawFifty)
        // One move short of that is still a game.
        XCTAssertEqual(ChessRules.status(ChessPosition.fromFen("4k3/8/8/8/8/8/8/R3K3 w - - 99 80")), .ongoing)
    }

    // Threefold repetition is counted by comparing position keys, so a
    // position reached again by a different route must give the same key.
    func testReturningToAPositionGivesTheSameKey() {
        let start = ChessPosition.start()
        var pos = start
        // 1. Nf3 Nf6 2. Ng1 Ng8
        for (from, to) in [(62, 45), (6, 21), (45, 62), (21, 6)] {
            pos = ChessRules.apply(pos, ChessMove(from: from, to: to))
        }
        XCTAssertEqual(pos.key(), start.key())
        XCTAssertNotEqual(ChessRules.apply(start, e2e4).key(), start.key())
    }

    func testBotFindsMateInOne() {
        let pos = ChessPosition.fromFen("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1")
        guard let move = ChessBot.choose(pos, difficulty: "MEDIUM") else {
            XCTFail("the bot returned no move")
            return
        }
        XCTAssertEqual(ChessRules.status(ChessRules.apply(pos, move)), .checkmate)
    }

    func testBotAlwaysReturnsALegalMove() {
        var pos = ChessPosition.start()
        for _ in 0..<12 {
            guard let move = ChessBot.choose(pos, difficulty: "EASY") else { return }
            XCTAssertTrue(ChessRules.legalMoves(pos).contains(move))
            pos = ChessRules.apply(pos, move)
        }
    }

    func testBotHasNoMoveWhenTheGameIsOver() {
        let mated = ChessPosition.fromFen("R5k1/5ppp/8/8/8/8/8/4K3 b - - 0 1")
        XCTAssertNil(ChessBot.choose(mated, difficulty: "HARD"))
    }
}
