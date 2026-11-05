import SwiftUI

/// Mirrors ChessActivity + ChessView: chess against the computer (you are
/// White) or two people sharing one phone. The rules and the bot are in
/// ChessEngine.swift; this screen draws the board from SwiftUI views (no
/// Canvas, to stay within the iOS 14 rules in CLAUDE.md), connects taps to
/// moves and shows who is to move and how the game ended.
struct ChessView: View {
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
    @State private var promotionOptions: [ChessMove] = []
    @State private var showPromotion = false
    @State private var showFeedback = false
    @State private var showReport = false

    private var isBotGame: Bool { selection.isBot }
    private var difficulty: String { selection.difficulty ?? "EASY" }

    // Unicode chess characters, index = piece type. The trailing variation
    // selector (\u{FE0E}) asks iOS for the text version of the pawn instead of
    // the emoji version.
    private let glyphs = ["", "\u{265F}\u{FE0E}", "\u{265E}\u{FE0E}", "\u{265D}\u{FE0E}",
                          "\u{265C}\u{FE0E}", "\u{265B}\u{FE0E}", "\u{265A}\u{FE0E}"]

    var body: some View {
        VStack(spacing: 8) {
            Text("\u{265E} Chess")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 8)

            Text(statusText)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: 0xFFEB3B))

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                board(side: side)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button("NEW GAME") { newGame() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: 0x4E342E))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button("Back") { gameId += 1; router.pop() }
                Button("Home") { gameId += 1; router.popToRoot() }
                Button("Feedback") { showFeedback = true }
                Button("Report") { showReport = true }
            }
            .font(.system(size: 14))
            .foregroundColor(Color(hex: 0x333333))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x4E342E).ignoresSafeArea())
        .confettiOverlay(confetti)
        .onAppear { if seen.isEmpty { newGame() } }
        .onDisappear { gameId += 1 }
        .actionSheet(isPresented: $showPromotion) {
            ActionSheet(
                title: Text("Promote your pawn to"),
                buttons: [
                    promotionButton("Queen \u{265B}", Chess.queen),
                    promotionButton("Rook \u{265C}", Chess.rook),
                    promotionButton("Bishop \u{265D}", Chess.bishop),
                    promotionButton("Knight \u{265E}", Chess.knight),
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "CHESS") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "CHESS") }
    }

    // MARK: - Drawing

    private func board(side: CGFloat) -> some View {
        let cell = side / 8
        let checkSquare = ChessRules.inCheck(pos, white: pos.whiteToMove)
            ? ChessRules.kingSquare(pos.board, white: pos.whiteToMove) : -1
        let targets = Set(legal.filter { $0.from == selected }.map { $0.to })
        return VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { c in
                        square(r * 8 + c, r: r, c: c, cell: cell, checkSquare: checkSquare, targets: targets)
                    }
                }
            }
        }
    }

    private func square(_ sq: Int, r: Int, c: Int, cell: CGFloat, checkSquare: Int, targets: Set<Int>) -> some View {
        let piece = pos.board[sq]
        let isEnPassant = sq == pos.ep && selected >= 0 && abs(pos.board[selected]) == Chess.pawn
        return ZStack {
            Rectangle().fill((r + c) % 2 == 0 ? Color(hex: 0xF2E3C6) : Color(hex: 0x8D6E4C))
            if let last = lastMove, sq == last.from || sq == last.to {
                Rectangle().fill(Color(hex: 0xFFEB3B, opacity: 0.4))
            }
            if sq == checkSquare { Rectangle().fill(Color(hex: 0xF44336, opacity: 0.53)) }
            if sq == selected { Rectangle().fill(Color(hex: 0x4CAF50, opacity: 0.53)) }
            if piece != 0 { pieceGlyph(piece, cell: cell) }
            if targets.contains(sq) {
                // A dot on empty squares, a ring on captures (en passant included).
                if piece != 0 || isEnPassant {
                    Circle().stroke(Color(hex: 0x304FFE, opacity: 0.67), lineWidth: cell * 0.07)
                        .frame(width: cell * 0.88, height: cell * 0.88)
                } else {
                    Circle().fill(Color(hex: 0x304FFE, opacity: 0.53))
                        .frame(width: cell * 0.32, height: cell * 0.32)
                }
            }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture { onSquareTapped(sq) }
    }

    // The solid glyphs are used for both colours; White is painted white
    // with a dark outline (four tiny offset shadows), Black is plain dark.
    private func pieceGlyph(_ piece: Int, cell: CGFloat) -> some View {
        let text = Text(glyphs[abs(piece)]).font(.system(size: cell * 0.82))
        return Group {
            if piece > 0 {
                text.foregroundColor(.white)
                    .shadow(color: Color(hex: 0x1B1B1B), radius: 0, x: 1, y: 0)
                    .shadow(color: Color(hex: 0x1B1B1B), radius: 0, x: -1, y: 0)
                    .shadow(color: Color(hex: 0x1B1B1B), radius: 0, x: 0, y: 1)
                    .shadow(color: Color(hex: 0x1B1B1B), radius: 0, x: 0, y: -1)
            } else {
                text.foregroundColor(Color(hex: 0x1B1B1B))
            }
        }
    }

    private func promotionButton(_ title: String, _ type: Int) -> ActionSheet.Button {
        let myGame = gameId
        return .default(Text(title)) {
            // Ignore the choice if the game was restarted or left meanwhile.
            guard myGame == gameId else { return }
            if let move = promotionOptions.first(where: { $0.promo == type }) { play(move) }
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
        updateStatus()
    }

    private func onSquareTapped(_ sq: Int) {
        if gameOver || botThinking { return }
        if isBotGame && !pos.whiteToMove { return }

        let movesHere = legal.filter { $0.from == selected && $0.to == sq }
        if selected != -1 && !movesHere.isEmpty {
            if movesHere.count > 1 {
                // A pawn reaching the last row: all four promotion moves exist, so ask which one.
                promotionOptions = movesHere
                showPromotion = true
            } else {
                play(movesHere[0])
            }
            return
        }
        let piece = pos.board[sq]
        // Tapping the selected piece again deselects it.
        if sq != selected && piece != 0 && (piece > 0) == pos.whiteToMove && legal.contains(where: { $0.from == sq }) {
            selected = sq
        } else {
            selected = -1
        }
    }

    private func play(_ move: ChessMove) {
        pos = ChessRules.apply(pos, move)
        seen.append(pos.key())
        lastMove = move
        selected = -1
        legal = ChessRules.legalMoves(pos)
        updateStatus()
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
                if let move = move { play(move) } else { updateStatus() }
            }
        }
    }

    private func updateStatus() {
        let check = ChessRules.inCheck(pos, white: pos.whiteToMove)
        let sideName = pos.whiteToMove ? "White" : "Black"
        let repeated = seen.filter { $0 == seen.last }.count >= 3
        switch ChessRules.status(pos, legal: legal) {
        case .checkmate:
            gameOver = true
            let whiteWon = !pos.whiteToMove
            let humanWon = !isBotGame || whiteWon
            if !isBotGame {
                statusText = "Checkmate! \(whiteWon ? "White" : "Black") wins! \u{1F389}"
            } else if whiteWon {
                statusText = "Checkmate! You win! \u{1F389}"
            } else {
                statusText = "Checkmate - the bot wins"
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
    ChessView(selection: GameSelection(gameType: "CHESS", difficulty: "EASY", isBot: true))
        .environmentObject(Router())
}
