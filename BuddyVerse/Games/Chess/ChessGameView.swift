import SwiftUI

/// Mirrors ChessActivity: chess against the computer (you are White) or two
/// people sharing one phone. The rules and the bot are in ChessEngine.swift;
/// this screen connects taps to moves and shows who is to move and how the
/// game ended. There is no online play yet, same as Android.
struct ChessGameView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    @State private var pos = ChessPosition.start()
    // Every position reached this game, to spot the same position three times.
    @State private var seen: [String] = []
    @State private var legal: [ChessMove] = []
    @State private var selected = -1
    @State private var lastMove: ChessMove?
    @State private var gameOver = false
    @State private var botThinking = false
    @State private var statusText = "White to move"
    // Bumped on New Game and on exit so a bot that is still thinking about an
    // old game can't move in the new one.
    @State private var gameId = 0
    @State private var promotionChoices: [ChessMove] = []
    @State private var showPromotion = false
    @State private var showFeedback = false
    @State private var showReport = false

    private var isBotGame: Bool { selection.isBot }
    private var difficulty: String { selection.difficulty ?? "EASY" }

    // The solid glyphs are used for both colours; White is just painted white
    // with a dark outline. The trailing variation selector asks for the text
    // version of the pawn instead of the emoji version.
    private let glyphs = ["", "♟\u{FE0E}", "♞\u{FE0E}", "♝\u{FE0E}", "♜\u{FE0E}", "♛\u{FE0E}", "♚\u{FE0E}"]

    var body: some View {
        VStack(spacing: 8) {
            Text("♞ Chess")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 8)

            Text(statusText)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: 0xFFEB3B))

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                boardView(cell: side / 8)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button("NEW GAME") { newGame() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: 0x4E342E))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

            HStack(spacing: 6) {
                smallButton("Back") { router.pop() }
                smallButton("Home") { router.popToRoot() }
                smallButton("Feedback") { showFeedback = true }
                smallButton("Report") { showReport = true }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x4E342E).ignoresSafeArea())
        .confettiOverlay(confetti)
        .onAppear { if seen.isEmpty { newGame() } }
        .onDisappear {
            // The bot's callback is ignored once gameId changes, so it could
            // never clear botThinking itself and the board would stay locked.
            gameId += 1
            botThinking = false
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "CHESS") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "CHESS") }
        .actionSheet(isPresented: $showPromotion) {
            ActionSheet(
                title: Text("Promote your pawn to"),
                buttons: [
                    .default(Text("Queen ♛")) { promote(to: Chess.queen) },
                    .default(Text("Rook ♜")) { promote(to: Chess.rook) },
                    .default(Text("Bishop ♝")) { promote(to: Chess.bishop) },
                    .default(Text("Knight ♞")) { promote(to: Chess.knight) },
                    .cancel()
                ]
            )
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13))
            .lineLimit(1)
            .foregroundColor(Color(hex: 0x333333))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .buttonStyle(.plain)
    }

    // MARK: - Board

    private var targets: Set<Int> {
        Set(legal.filter { $0.from == selected }.map { $0.to })
    }

    private var checkSquare: Int {
        ChessRules.inCheck(pos, white: pos.whiteToMove) ? ChessRules.kingSquare(pos.board, white: pos.whiteToMove) : -1
    }

    private func boardView(cell: CGFloat) -> some View {
        let targetSquares = targets
        let check = checkSquare
        return VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { c in
                        squareView(r * 8 + c, cell: cell, targets: targetSquares, check: check)
                    }
                }
            }
        }
    }

    private func squareView(_ sq: Int, cell: CGFloat, targets: Set<Int>, check: Int) -> some View {
        let r = sq / 8
        let c = sq % 8
        let piece = pos.board[sq]
        let isLast = lastMove.map { $0.from == sq || $0.to == sq } ?? false
        // An en passant capture lands on an empty square, but is still a capture.
        let isEnPassant = selected >= 0 && sq == pos.ep && abs(pos.board[selected]) == Chess.pawn
        return ZStack {
            Rectangle().fill((r + c) % 2 == 0 ? Color(hex: 0xF2E3C6) : Color(hex: 0x8D6E4C))
            if isLast { Rectangle().fill(Color(hex: 0xFFEB3B, opacity: 0.4)) }
            if sq == check { Rectangle().fill(Color(hex: 0xF44336, opacity: 0.53)) }
            if sq == selected { Rectangle().fill(Color(hex: 0x4CAF50, opacity: 0.53)) }
            if piece != 0 {
                pieceText(piece, cell: cell)
            }
            if targets.contains(sq) {
                if piece != 0 || isEnPassant {
                    Circle()
                        .stroke(Color(hex: 0x304FFE, opacity: 0.67), lineWidth: cell * 0.07)
                        .frame(width: cell * 0.88, height: cell * 0.88)
                } else {
                    Circle()
                        .fill(Color(hex: 0x304FFE, opacity: 0.53))
                        .frame(width: cell * 0.32, height: cell * 0.32)
                }
            }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture { onSquareTapped(sq) }
        // One labelled element per square, so VoiceOver can read the board
        // ("e2, white pawn") and tests can tap a square by name.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(squareLabel(sq)))
        .accessibilityIdentifier("chess-sq-\(sq)")
    }

    private func squareLabel(_ sq: Int) -> String {
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let names = ["", "pawn", "knight", "bishop", "rook", "queen", "king"]
        let piece = pos.board[sq]
        let name = "\(files[sq % 8])\(8 - sq / 8)"
        if piece == 0 { return name }
        return "\(name), \(piece > 0 ? "white" : "black") \(names[abs(piece)])"
    }

    @ViewBuilder
    private func pieceText(_ piece: Int, cell: CGFloat) -> some View {
        let glyph = glyphs[abs(piece)]
        let size = cell * 0.82
        if piece > 0 {
            // A white piece with a thin dark outline, made from four tiny shadows.
            Text(glyph)
                .font(.system(size: size))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 0, x: 1, y: 0)
                .shadow(color: .black, radius: 0, x: -1, y: 0)
                .shadow(color: .black, radius: 0, x: 0, y: 1)
                .shadow(color: .black, radius: 0, x: 0, y: -1)
        } else {
            Text(glyph)
                .font(.system(size: size))
                .foregroundColor(Color(hex: 0x1B1B1B))
        }
    }

    // MARK: - Game flow

    private func newGame() {
        gameId += 1
        pos = ChessPosition.start()
        seen = [pos.key()]
        legal = ChessRules.legalMoves(pos)
        selected = -1
        lastMove = nil
        gameOver = false
        botThinking = false
        refreshStatus()
    }

    private func onSquareTapped(_ sq: Int) {
        if gameOver || botThinking { return }
        if isBotGame && !pos.whiteToMove { return }

        let movesHere = legal.filter { $0.from == selected && $0.to == sq }
        if selected != -1 && !movesHere.isEmpty {
            if movesHere.count > 1 {
                promotionChoices = movesHere
                showPromotion = true
            } else {
                play(movesHere[0])
            }
            return
        }
        let piece = pos.board[sq]
        // Tapping the selected piece again puts it down.
        selected = (sq != selected && piece != 0 && (piece > 0) == pos.whiteToMove && legal.contains { $0.from == sq }) ? sq : -1
    }

    private func promote(to type: Int) {
        if let move = promotionChoices.first(where: { $0.promo == type }) { play(move) }
        promotionChoices = []
    }

    private func play(_ move: ChessMove) {
        pos = ChessRules.apply(pos, move)
        seen.append(pos.key())
        lastMove = move
        selected = -1
        legal = ChessRules.legalMoves(pos)
        refreshStatus()
        if !gameOver && isBotGame && !pos.whiteToMove { startBot() }
    }

    private func startBot() {
        botThinking = true
        statusText = "Bot is thinking..."
        let myGame = gameId
        let snapshot = pos
        let level = difficulty
        DispatchQueue.global(qos: .userInitiated).async {
            let move = ChessBot.choose(snapshot, difficulty: level)
            DispatchQueue.main.async {
                guard myGame == gameId else { return }
                botThinking = false
                if let move = move { play(move) } else { refreshStatus() }
            }
        }
    }

    private func refreshStatus() {
        let check = ChessRules.inCheck(pos, white: pos.whiteToMove)
        let sideName = pos.whiteToMove ? "White" : "Black"
        let last = seen.last
        let repeated = seen.filter { $0 == last }.count >= 3
        switch ChessRules.status(pos, legal: legal) {
        case .checkmate:
            gameOver = true
            let whiteWon = !pos.whiteToMove
            let humanWon = !isBotGame || whiteWon
            if !isBotGame {
                statusText = "Checkmate! \(whiteWon ? "White" : "Black") wins! 🎉"
            } else {
                statusText = whiteWon ? "Checkmate! You win! 🎉" : "Checkmate - the bot wins"
            }
            if humanWon { confetti.start() }
        case .stalemate: endDraw("Draw - stalemate")
        case .drawMaterial: endDraw("Draw - not enough pieces left to win")
        case .drawFifty: endDraw("Draw - 50 moves with no capture or pawn move")
        case .ongoing:
            if repeated {
                endDraw("Draw - the same position three times")
            } else if !botThinking {
                let who = isBotGame ? "Your move" : "\(sideName) to move"
                statusText = check ? "\(who) - check!" : who
            }
        }
    }

    private func endDraw(_ text: String) {
        gameOver = true
        statusText = text
    }
}

#Preview {
    ChessGameView(selection: GameSelection(gameType: "CHESS", difficulty: "EASY", isBot: true))
        .environmentObject(Router())
}
