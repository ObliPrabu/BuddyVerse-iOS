import SwiftUI

/// Mirrors ChessActivity.kt + ChessView.kt. Three ways to play: against the
/// computer (you are White), two people sharing one phone, or two phones over
/// the internet. The rules and the bot are in ChessEngine.swift, the online
/// message format is in ChessOnline.swift; this screen connects taps to moves,
/// draws the board and shows who is to move and how the game ended.
///
/// Online: colours come from the room's seat order and the round number (see
/// ChessWire), the player with Black sees the board turned around, and every
/// message from the other phone is checked (sender, turn, exact legal move)
/// before it touches the board.
struct ChessView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    private let difficulty: String
    private let isBotGame: Bool
    private let isNearbyGame: Bool
    private let players: [Player]

    init(selection: GameSelection) {
        self.difficulty = selection.difficulty ?? "EASY"
        self.isBotGame = selection.isBot
        self.isNearbyGame = selection.isNearby
        self.players = selection.players ?? []
    }

    private struct PendingPromotion {
        let options: [ChessMove]
        let gameId: Int
        let roundId: Int
    }

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

    // --- Online ("Two Phones") mode ---
    @State private var myId: String?
    // Bumped on every new game; tags each message so one still in flight when
    // a new game starts is dropped (see ChessWire).
    @State private var roundId = 0
    // Set when a game ends by resignation, since the board itself is not over.
    @State private var resultText: String?

    @State private var pendingPromotion: PendingPromotion?
    @State private var showResignConfirm = false
    @State private var didSetup = false
    @State private var didHandleDisconnect = false
    @State private var toastMessage: String?
    @State private var toastToken = UUID()
    @State private var showFeedback = false
    @State private var showReport = false

    private let lightColor = Color(hex: 0xF2E3C6)
    private let darkColor = Color(hex: 0x8D6E4C)
    // Index = piece type (1 pawn ... 6 king). The trailing variation selector
    // asks for the text version of the pawn instead of the emoji version.
    private let glyphs = ["", "\u{265F}\u{FE0E}", "\u{265E}\u{FE0E}", "\u{265D}\u{FE0E}",
                          "\u{265C}\u{FE0E}", "\u{265B}\u{FE0E}", "\u{265A}\u{FE0E}"]

    // Seat 0 is the host, seat 1 the guest - the same order on both phones.
    private var mySeat: Int { players.firstIndex { $0.id == myId } ?? -1 }
    private var myIsWhite: Bool { mySeat == ChessWire.whiteSeat(roundId) }
    private var boardFlipped: Bool { isNearbyGame && !myIsWhite }

    var body: some View {
        ZStack {
            Color(hex: 0x4E342E).ignoresSafeArea()

            VStack(spacing: 0) {
                Text("\u{265E} Chess")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)

                Text(statusText)
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: 0xFFEB3B))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                boardView

                Button("NEW GAME") { onNewGamePressed() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: 0x4E342E))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if isNearbyGame {
                    Button("RESIGN") { if !gameOver { showResignConfirm = true } }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: 0x333333))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.bottom, 6)
                }

                HStack(spacing: 6) {
                    smallButton("Back") { router.pop() }
                    smallButton("Home") { router.popToRoot() }
                    smallButton("Feedback") { showFeedback = true }
                    smallButton("Report") { showReport = true }
                }
            }
            .buttonStyle(.plain)
            .padding(12)

            toastOverlay
        }
        .confettiOverlay(confetti)
        .onAppear { setupIfNeeded() }
        .onDisappear {
            gameId += 1
            if isNearbyGame { InternetConnectionManager.shared.stop() }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "CHESS") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "CHESS") }
        .actionSheet(isPresented: Binding(
            get: { pendingPromotion != nil },
            set: { if !$0 { pendingPromotion = nil } }
        )) { promotionSheet() }
        .alert(isPresented: $showResignConfirm) {
            Alert(
                title: Text("Resign this game?"),
                primaryButton: .destructive(Text("Resign")) { confirmResign() },
                secondaryButton: .cancel(Text("Keep playing"))
            )
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13))
            .foregroundColor(Color(hex: 0x333333))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Board drawing

    private var targets: Set<Int> {
        Set(legal.filter { $0.from == selected }.map { $0.to })
    }

    private var checkSquare: Int {
        ChessRules.inCheck(pos, white: pos.whiteToMove) ? ChessRules.kingSquare(pos.board, white: pos.whiteToMove) : -1
    }

    private var boardView: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 8
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { drawRow in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { drawCol in
                            squareView(squareAt(drawRow: drawRow, drawCol: drawCol), drawRow: drawRow, drawCol: drawCol, cell: cell)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // Squares keep their normal numbers; only where they are drawn and tapped
    // changes when the board is turned around for Black.
    private func squareAt(drawRow: Int, drawCol: Int) -> Int {
        boardFlipped ? (7 - drawRow) * 8 + (7 - drawCol) : drawRow * 8 + drawCol
    }

    private func squareView(_ sq: Int, drawRow: Int, drawCol: Int, cell: CGFloat) -> some View {
        let piece = pos.board[sq]
        let isTarget = targets.contains(sq)
        return ZStack {
            Rectangle().fill((drawRow + drawCol) % 2 == 0 ? lightColor : darkColor)
            if let m = lastMove, sq == m.from || sq == m.to {
                Rectangle().fill(Color(hex: 0xFFEB3B, opacity: 0.4))
            }
            if sq == checkSquare {
                Rectangle().fill(Color(hex: 0xF44336, opacity: 0.53))
            }
            if sq == selected {
                Rectangle().fill(Color(hex: 0x4CAF50, opacity: 0.53))
            }
            if piece != 0 {
                pieceGlyph(piece, cell: cell)
            }
            if isTarget {
                if piece != 0 {
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

    // White pieces are the solid glyph painted white with a dark outline
    // (four dark copies nudged around it); Black pieces are plain dark.
    private func pieceGlyph(_ piece: Int, cell: CGFloat) -> some View {
        let glyph = glyphs[abs(piece)]
        let size = cell * 0.82
        let o = max(1, cell * 0.03)
        let dark = Color(hex: 0x1B1B1B)
        return ZStack {
            if piece > 0 {
                Text(glyph).font(.system(size: size)).foregroundColor(dark).offset(x: o, y: 0)
                Text(glyph).font(.system(size: size)).foregroundColor(dark).offset(x: -o, y: 0)
                Text(glyph).font(.system(size: size)).foregroundColor(dark).offset(x: 0, y: o)
                Text(glyph).font(.system(size: size)).foregroundColor(dark).offset(x: 0, y: -o)
                Text(glyph).font(.system(size: size)).foregroundColor(.white)
            } else {
                Text(glyph).font(.system(size: size)).foregroundColor(dark)
            }
        }
        .allowsHitTesting(false)
    }

    private var toastOverlay: some View {
        VStack {
            Spacer()
            if let toastMessage {
                Text(toastMessage)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func showToast(_ text: String, duration: Double = 2.0) {
        toastMessage = text
        let token = UUID()
        toastToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if toastToken == token { toastMessage = nil }
        }
    }

    // MARK: - Setup

    private func setupIfNeeded() {
        guard !didSetup else { return }
        didSetup = true

        guard isNearbyGame else {
            newGame()
            return
        }
        let me = InternetConnectionManager.shared.myPlayerId()
        myId = me
        // Chess is exactly two players and we must be one of them.
        guard players.count == 2, players.contains(where: { $0.id == me }) else {
            showToast("Could not start the online game.")
            router.pop()
            return
        }
        // Everything goes through onMessageWithSender so each move can be
        // checked against who really sent it. Attached after the first
        // newGame() so a message buffered during the lobby is replayed onto a
        // fresh board, not wiped by it.
        newGame()
        InternetConnectionManager.shared.setListeners(
            onMessage: { _ in },
            onDisconnected: { DispatchQueue.main.async { handleOpponentDisconnected() } },
            onMessageWithSender: { sender, msg in DispatchQueue.main.async { receiveNearbyMessage(sender, msg) } }
        )
    }

    private func handleOpponentDisconnected() {
        guard !didHandleDisconnect else { return }
        didHandleDisconnect = true
        // The ZStack Router keeps this view mounted when another screen is
        // pushed on top, so stop explicitly here, as Tic-Tac-Toe does.
        InternetConnectionManager.shared.stop()
        router.push(.opponentDisconnected)
    }

    // MARK: - Game flow

    private func onNewGamePressed() {
        if isNearbyGame {
            // Same as Tic-Tac-Toe's Reset: a new game is a new round, and
            // the colours swap because White is picked from the round.
            roundId += 1
            InternetConnectionManager.shared.sendMessage(ChessWire.reset(roundId))
        }
        newGame()
    }

    private func newGame() {
        gameId += 1
        pos = ChessPosition.start()
        seen = [pos.key()]
        legal = ChessRules.legalMoves(pos)
        selected = -1
        lastMove = nil
        gameOver = false
        botThinking = false
        resultText = nil
        pendingPromotion = nil
        updateStatus()
    }

    private func onSquareTapped(_ sq: Int) {
        if gameOver || botThinking { return }
        if isBotGame && !pos.whiteToMove { return }
        if isNearbyGame && pos.whiteToMove != myIsWhite { return } // opponent's turn

        let movesHere = legal.filter { $0.from == selected && $0.to == sq }
        if selected != -1 && !movesHere.isEmpty {
            if movesHere.count > 1 {
                // A pawn reaching the last row: all four promotion moves exist, so ask which one.
                pendingPromotion = PendingPromotion(options: movesHere, gameId: gameId, roundId: roundId)
            } else {
                play(movesHere[0])
            }
            return
        }
        let piece = pos.board[sq]
        selected = (piece != 0 && (piece > 0) == pos.whiteToMove && legal.contains { $0.from == sq }) ? sq : -1
    }

    private func promotionSheet() -> ActionSheet {
        guard let pending = pendingPromotion else { return ActionSheet(title: Text("")) }
        let choices: [(String, Int)] = [
            ("Queen \u{265B}", Chess.queen), ("Rook \u{265C}", Chess.rook),
            ("Bishop \u{265D}", Chess.bishop), ("Knight \u{265E}", Chess.knight)
        ]
        var buttons: [ActionSheet.Button] = choices.map { choice in
            ActionSheet.Button.default(Text(choice.0)) {
                // If the game moved on while the sheet was open (the
                // opponent resigned or started a new game), do nothing.
                if gameOver || pending.gameId != gameId || pending.roundId != roundId { return }
                if let move = pending.options.first(where: { $0.promo == choice.1 }) { play(move) }
            }
        }
        buttons.append(.cancel())
        return ActionSheet(title: Text("Promote your pawn to"), buttons: buttons)
    }

    private func play(_ move: ChessMove, fromPeer: Bool = false) {
        // Tag with the round the move belongs to and send before anything
        // else can change it.
        if isNearbyGame && !fromPeer {
            InternetConnectionManager.shared.sendMessage(ChessWire.move(roundId, move))
        }
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
                if let move { play(move) } else { updateStatus() }
            }
        }
    }

    private func updateStatus() {
        if let text = resultText {
            statusText = text
            return
        }
        let sideName = pos.whiteToMove ? "White" : "Black"
        let check = ChessRules.inCheck(pos, white: pos.whiteToMove)
        let repeated = seen.filter { $0 == seen.last }.count >= 3
        switch ChessRules.status(pos, legal: legal) {
        case .checkmate:
            let alreadyOver = gameOver
            gameOver = true
            let whiteWon = !pos.whiteToMove
            let humanWon = isNearbyGame ? (whiteWon == myIsWhite) : (!isBotGame || whiteWon)
            if isNearbyGame {
                statusText = humanWon ? "Checkmate! You win! \u{1F389}" : "Checkmate - your friend wins"
            } else if !isBotGame {
                statusText = "Checkmate! \(whiteWon ? "White" : "Black") wins! \u{1F389}"
            } else {
                statusText = whiteWon ? "Checkmate! You win! \u{1F389}" : "Checkmate - the bot wins"
            }
            if humanWon && !alreadyOver { confetti.start() }
        case .stalemate: endDraw("Draw - stalemate")
        case .drawMaterial: endDraw("Draw - not enough pieces left to win")
        case .drawFifty: endDraw("Draw - 50 moves with no capture or pawn move")
        case .ongoing:
            if repeated {
                endDraw("Draw - the same position three times")
            } else if !botThinking {
                let who: String
                if isNearbyGame {
                    who = pos.whiteToMove == myIsWhite ? "Your move" : "Friend's move"
                } else if isBotGame {
                    who = "Your move"
                } else {
                    who = "\(sideName) to move"
                }
                statusText = check ? "\(who) - check!" : who
            }
        }
    }

    private func endDraw(_ text: String) {
        gameOver = true
        statusText = text
    }

    // MARK: - Online

    private func confirmResign() {
        if gameOver { return }
        InternetConnectionManager.shared.sendMessage(ChessWire.resign(roundId))
        gameOver = true
        resultText = "You resigned"
        updateStatus()
    }

    // Everything a peer sends is checked before it touches the board.
    private func receiveNearbyMessage(_ sender: String, _ raw: String) {
        if sender == myId { return }
        guard let senderSeat = players.firstIndex(where: { $0.id == sender }) else { return }
        guard let msg = ChessWire.parse(raw) else { return }

        if case .reset(let newRound) = msg {
            guard ChessWire.acceptableResetRound(current: roundId, received: newRound) else { return }
            roundId = newRound
            newGame()
            return
        }
        if msg.round != roundId || gameOver { return } // stale, or the game is already decided

        switch msg {
        case .move(_, let received):
            // Must be the sender's turn and a move the rules really allow.
            guard senderSeat == ChessWire.seatToMove(pos, round: roundId) else { return }
            guard let legalMove = ChessWire.validate(pos, received) else { return }
            play(legalMove, fromPeer: true)
        case .resign:
            gameOver = true
            resultText = "\(players[senderSeat].name) resigned - you win! \u{1F389}"
            confetti.start()
            updateStatus()
        case .reset:
            break
        }
    }
}
