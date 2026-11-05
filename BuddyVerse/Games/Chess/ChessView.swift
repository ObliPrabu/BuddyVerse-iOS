import SwiftUI
import UIKit
import UserNotifications

/// Mirrors ChessActivity.kt + ChessView.kt. Three ways to play: against the
/// computer (you are White), two people sharing one phone, or two phones over
/// the internet. The rules and the bot are in ChessEngine.swift, the online
/// message format and the clock are in ChessOnline.swift; this screen connects
/// taps to moves, draws the board and shows who is to move and how the game
/// ended.
///
/// Online: colours come from the room's seat order and the round number (see
/// ChessWire), the player with Black sees the board turned around, and every
/// message from the other phone is checked (sender, turn, exact legal move)
/// before it touches the board. Online games also have an optional clock
/// (chosen by the host on the lobby screen), a Draw and a Takeback button -
/// both need the other player to agree - a New Game that needs agreement
/// unless the game is over, and a notification when your friend moves while
/// you are away.
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
        let ply: Int
    }

    // Everything the screen can ask the player in a dialog. One at a time:
    // SwiftUI only shows a single alert per view.
    private enum ChessAlert: Identifiable {
        case resign
        case drawOffer(gameId: Int, ply: Int)
        case takeback(gameId: Int, ply: Int)
        case newGame(gameId: Int)

        var id: String {
            switch self {
            case .resign: return "resign"
            case .drawOffer: return "draw"
            case .takeback: return "takeback"
            case .newGame: return "newgame"
            }
        }
    }

    @State private var pos = ChessPosition.start()
    // Every position reached this game, to spot the same position three times.
    @State private var seen: [String] = []
    // The position before each move and the moves themselves, so a takeback
    // can step back. playedMoves.count is the "ply" the online messages mention.
    @State private var prevPositions: [ChessPosition] = []
    @State private var playedMoves: [ChessMove] = []
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
    // Set when a game ends some way the board itself doesn't show: resignation,
    // running out of time, or an agreed draw.
    @State private var resultText: String?
    // True while an offer or request of mine is waiting for an answer.
    @State private var drawOfferedByMe = false
    @State private var takebackRequestedByMe = false
    @State private var newGameOfferedByMe = false

    // --- Online clock (0 = no clock). The host's choice, told to the guest in a CLOCK message. ---
    @State private var clockSeconds = 0
    @State private var clock: ChessClock?
    @State private var myClockText = ""
    @State private var oppClockText = ""
    private let clockTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    @State private var pendingPromotion: PendingPromotion?
    @State private var activeAlert: ChessAlert?
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

    // A friend's TIMEOUT is believed if our own count of their clock is at most
    // this far from zero (network delay makes the two counts differ a little).
    private let timeoutToleranceMs: Int64 = 3_000
    // If our friend's clock is this far below zero and we never heard from
    // them, we call it ourselves.
    private let failsafeMs: Int64 = 10_000

    // Seat 0 is the host, seat 1 the guest - the same order on both phones.
    private var mySeat: Int { players.firstIndex { $0.id == myId } ?? -1 }
    private var myIsWhite: Bool { mySeat == ChessWire.whiteSeat(roundId) }
    private var boardFlipped: Bool { isNearbyGame && !myIsWhite }
    private var friendName: String { players.first { $0.id != myId }?.name ?? "Your friend" }

    private var newGameTitle: String {
        guard isNearbyGame else { return "NEW GAME" }
        if gameOver { return "NEW GAME" }
        return newGameOfferedByMe ? "WAITING FOR ANSWER..." : "PROPOSE NEW GAME"
    }

    // You can take back your own last move, but only while your friend has not
    // replied yet (it is their turn).
    private var canRequestTakeback: Bool {
        isNearbyGame && !gameOver && !playedMoves.isEmpty && !takebackRequestedByMe && pos.whiteToMove != myIsWhite
    }

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

                if clock != nil {
                    Text(oppClockText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.bottom, 4)
                }

                boardView

                if clock != nil {
                    Text(myClockText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                }

                Button(newGameTitle) { onNewGamePressed() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: 0x4E342E))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if isNearbyGame {
                    // Online games only: resign, offer a draw, ask to take back your last move.
                    HStack(spacing: 6) {
                        actionButton("RESIGN", enabled: !gameOver) { activeAlert = .resign }
                        actionButton("DRAW?", enabled: !gameOver && !drawOfferedByMe) { offerDraw() }
                        actionButton("TAKEBACK?", enabled: canRequestTakeback) { requestTakeback() }
                    }
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
        .onReceive(clockTimer) { _ in updateClocks() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Back in the app: the "your friend moved" banner is out of date.
            LocalNotificationManager.shared.clearChessNotification()
            updateClocks()
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "CHESS") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "CHESS") }
        .actionSheet(isPresented: Binding(
            get: { pendingPromotion != nil },
            set: { if !$0 { pendingPromotion = nil } }
        )) { promotionSheet() }
        .alert(item: $activeAlert) { alert in chessAlert(alert) }
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

    private func actionButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Color(hex: 0x333333))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(enabled ? 1 : 0.4)
            .disabled(!enabled)
    }

    // MARK: - Dialogs

    private func chessAlert(_ alert: ChessAlert) -> Alert {
        switch alert {
        case .resign:
            return Alert(
                title: Text("Resign this game?"),
                primaryButton: .destructive(Text("Resign")) { confirmResign() },
                secondaryButton: .cancel(Text("Keep playing"))
            )
        case .drawOffer(let openedGame, let ply):
            return Alert(
                title: Text("Draw offer"),
                message: Text("\(friendName) offers a draw. Do you accept?"),
                primaryButton: .default(Text("Accept")) {
                    // A move, a new game or the game ending since the offer was
                    // made cancels it.
                    if gameOver || openedGame != gameId || ply != playedMoves.count {
                        showToast("That draw offer has expired.")
                        return
                    }
                    InternetConnectionManager.shared.sendMessage(ChessWire.drawAccept(roundId))
                    endDrawAgreed()
                },
                secondaryButton: .cancel(Text("Decline")) {
                    InternetConnectionManager.shared.sendMessage(ChessWire.drawDecline(roundId))
                }
            )
        case .takeback(let openedGame, let ply):
            return Alert(
                title: Text("Takeback request"),
                message: Text("\(friendName) wants to take back their last move. Allow it?"),
                primaryButton: .default(Text("Allow")) {
                    // If we moved in the meantime the request is stale.
                    if gameOver || openedGame != gameId || ply != playedMoves.count {
                        showToast("That takeback request has expired.")
                        InternetConnectionManager.shared.sendMessage(ChessWire.takebackDecline(roundId, ply))
                        return
                    }
                    InternetConnectionManager.shared.sendMessage(ChessWire.takebackAccept(roundId, ply))
                    undoLastMove()
                },
                secondaryButton: .cancel(Text("No")) {
                    InternetConnectionManager.shared.sendMessage(ChessWire.takebackDecline(roundId, ply))
                }
            )
        case .newGame(let openedGame):
            return Alert(
                title: Text("New game?"),
                message: Text("\(friendName) would like to stop this game and start a new one. Do you agree?"),
                primaryButton: .default(Text("Agree")) {
                    if openedGame != gameId {
                        showToast("That proposal has expired.")
                        return
                    }
                    startNextRound()
                },
                secondaryButton: .cancel(Text("Keep playing")) {
                    InternetConnectionManager.shared.sendMessage(ChessWire.newGameDecline(roundId))
                }
            )
        }
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
            // The squares sit to the right of a narrow strip holding the rank
            // numbers and above a strip holding the file letters, so the
            // labels never cover a piece.
            let margin = side * 0.055
            let cell = (side - margin) / 8
            let labelColor = Color(hex: 0xE8D5B5)
            let labelFont = Font.system(size: margin * 0.7, weight: .bold)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Numbers 1-8 down the left side. When the board is turned
                    // around for Black they run the other way, so they always
                    // name the square next to them.
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { drawRow in
                            Text("\(boardFlipped ? drawRow + 1 : 8 - drawRow)")
                                .font(labelFont)
                                .foregroundColor(labelColor)
                                .frame(width: margin, height: cell)
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { drawRow in
                            HStack(spacing: 0) {
                                ForEach(0..<8, id: \.self) { drawCol in
                                    squareView(squareAt(drawRow: drawRow, drawCol: drawCol), drawRow: drawRow, drawCol: drawCol, cell: cell)
                                }
                            }
                        }
                    }
                }
                // Letters a-h along the bottom.
                HStack(spacing: 0) {
                    Color.clear.frame(width: margin, height: margin)
                    ForEach(0..<8, id: \.self) { drawCol in
                        Text(String(Character(UnicodeScalar(UInt8(97 + (boardFlipped ? 7 - drawCol : drawCol))))))
                            .font(labelFont)
                            .foregroundColor(labelColor)
                            .frame(width: cell, height: margin)
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

    private func squareLabel(_ sq: Int) -> String {
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let names = ["", "pawn", "knight", "bishop", "rook", "queen", "king"]
        let piece = pos.board[sq]
        let name = "\(files[sq % 8])\(8 - sq / 8)"
        if piece == 0 { return name }
        return "\(name), \(piece > 0 ? "white" : "black") \(names[abs(piece)])"
    }

    private func squareView(_ sq: Int, drawRow: Int, drawCol: Int, cell: CGFloat) -> some View {
        let piece = pos.board[sq]
        let isTarget = targets.contains(sq)
        // An en passant capture lands on an empty square, but is still a capture.
        let isEnPassant = selected >= 0 && sq == pos.ep && abs(pos.board[selected]) == Chess.pawn
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
        // One labelled element per square, so VoiceOver can read the board
        // ("e2, white pawn") and tests can tap a square by name.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(squareLabel(sq)))
        .accessibilityIdentifier("chess-sq-\(sq)")
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
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
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
        // The host (seat 0) picked the clock on the lobby screen; the guest
        // finds out from the CLOCK message the host sends below.
        let iAmHost = players.firstIndex { $0.id == me } == 0
        if iAmHost {
            clockSeconds = ChessSettings.hostClockSeconds
            ChessSettings.hostClockSeconds = 0
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
        if iAmHost && clockSeconds > 0 {
            InternetConnectionManager.shared.sendMessage(ChessWire.clock(roundId, clockSeconds))
        }
        // Asked now, while the player is looking at the screen, so a "your friend
        // moved" notification can show later.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
        if !isNearbyGame {
            newGame()
        } else if gameOver {
            // The game is already decided (mate, resignation, time, draw), so
            // either player may start the next one. A new round swaps the colours.
            startNextRound()
        } else {
            proposeNewGame()
        }
    }

    // A finished game can simply be restarted, but a game in progress needs
    // both players to agree.
    private func startNextRound() {
        roundId += 1
        InternetConnectionManager.shared.sendMessage(ChessWire.reset(roundId))
        newGame()
    }

    private func proposeNewGame() {
        if newGameOfferedByMe {
            showToast("Still waiting for \(friendName) to answer.")
            return
        }
        newGameOfferedByMe = true
        InternetConnectionManager.shared.sendMessage(ChessWire.newGameOffer(roundId))
        showToast("New game proposed - waiting for \(friendName). To end this game yourself, resign or offer a draw.", duration: 3.5)
    }

    private func newGame() {
        gameId += 1
        pos = ChessPosition.start()
        seen = [pos.key()]
        prevPositions = []
        playedMoves = []
        legal = ChessRules.legalMoves(pos)
        selected = -1
        lastMove = nil
        gameOver = false
        botThinking = false
        resultText = nil
        pendingPromotion = nil
        drawOfferedByMe = false
        takebackRequestedByMe = false
        newGameOfferedByMe = false
        resetClock()
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
                pendingPromotion = PendingPromotion(options: movesHere, gameId: gameId, roundId: roundId, ply: playedMoves.count)
            } else {
                play(movesHere[0])
            }
            return
        }
        let piece = pos.board[sq]
        selected = (sq != selected && piece != 0 && (piece > 0) == pos.whiteToMove && legal.contains { $0.from == sq }) ? sq : -1
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
                if gameOver || pending.gameId != gameId || pending.roundId != roundId || pending.ply != playedMoves.count { return }
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
        prevPositions.append(pos)
        playedMoves.append(move)
        pos = ChessRules.apply(pos, move)
        seen.append(pos.key())
        lastMove = move
        selected = -1
        legal = ChessRules.legalMoves(pos)
        // A move settles any open offer or request, and hands the clock to the other side.
        drawOfferedByMe = false
        takebackRequestedByMe = false
        clock?.switchTo(pos.whiteToMove, now: nowMs())
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
        computeStatus()
        if gameOver { clock?.stop(now: nowMs()) }
        updateClocks()
    }

    private func computeStatus() {
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

    // MARK: - Online: resign, draw offers, takebacks

    private func confirmResign() {
        if gameOver { return }
        InternetConnectionManager.shared.sendMessage(ChessWire.resign(roundId))
        gameOver = true
        resultText = "You resigned"
        updateStatus()
    }

    private func offerDraw() {
        if gameOver || drawOfferedByMe { return }
        drawOfferedByMe = true
        InternetConnectionManager.shared.sendMessage(ChessWire.drawOffer(roundId))
        showToast("Draw offered - waiting for \(friendName).")
    }

    private func endDrawAgreed() {
        gameOver = true
        drawOfferedByMe = false
        resultText = "Draw - agreed by both players"
        updateStatus()
    }

    private func requestTakeback() {
        if !canRequestTakeback {
            showToast("You can only take back your move before your friend replies.")
            return
        }
        takebackRequestedByMe = true
        InternetConnectionManager.shared.sendMessage(ChessWire.takeback(roundId, playedMoves.count))
        showToast("Takeback requested - waiting for \(friendName).")
    }

    // Steps the board back one move on both phones (each does it when the
    // takeback is agreed), so the player who asked can move again.
    private func undoLastMove() {
        guard !playedMoves.isEmpty, let previous = prevPositions.popLast() else { return }
        pos = previous
        playedMoves.removeLast()
        seen.removeLast()
        lastMove = playedMoves.last
        legal = ChessRules.legalMoves(pos)
        selected = -1
        drawOfferedByMe = false
        takebackRequestedByMe = false
        // Nothing runs before White's first move; otherwise the clock goes back to the player who moves again.
        clock?.switchTo(playedMoves.isEmpty ? nil : pos.whiteToMove, now: nowMs())
        updateStatus()
    }

    // MARK: - Online: clock

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSinceReferenceDate * 1000) }

    private func resetClock() {
        clock = (isNearbyGame && clockSeconds > 0) ? ChessClock(totalMs: Int64(clockSeconds) * 1000) : nil
        updateClocks()
    }

    private func formatClock(_ ms: Int64) -> String {
        let total = max(0, ms + 999) / 1000 // round up, so 0:00 only shows at real zero
        return String(format: "%d:%02d", Int(total / 60), Int(total % 60))
    }

    private func updateClocks() {
        guard let c = clock else {
            myClockText = ""
            oppClockText = ""
            return
        }
        let now = nowMs()
        let myWhite = myIsWhite
        let mine = c.remaining(white: myWhite, now: now)
        let theirs = c.remaining(white: !myWhite, now: now)
        myClockText = "You   \(formatClock(mine))"
        oppClockText = "\(friendName)   \(formatClock(theirs))"
        if gameOver || playedMoves.isEmpty { return }
        let myTurn = pos.whiteToMove == myWhite
        if myTurn && mine <= 0 {
            // My own clock ran out: I lose, and I tell my friend.
            InternetConnectionManager.shared.sendMessage(ChessWire.timeout(roundId))
            gameOver = true
            resultText = "Time's up - you lose on time"
            updateStatus()
        } else if !myTurn && theirs <= -failsafeMs {
            // Normally my friend's phone tells me they ran out. If it never
            // does (phone asleep, signal lost), call it after a grace period.
            winOnTime()
        }
    }

    private func winOnTime() {
        if gameOver { return }
        gameOver = true
        resultText = "\(friendName) ran out of time - you win! \u{1F389}"
        confetti.start()
        updateStatus()
    }

    // MARK: - Online: notifications when your friend moves

    private func squareName(_ sq: Int) -> String {
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        return "\(files[sq % 8])\(8 - sq / 8)"
    }

    private func notifyFriendMoved(_ move: ChessMove) {
        let text = "\(squareName(move.from)) to \(squareName(move.to))"
        if UIApplication.shared.applicationState == .active {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showToast("\(friendName) moved: \(text)")
        } else {
            LocalNotificationManager.shared.notifyChessMove(friend: friendName, text: text)
        }
    }

    // MARK: - Online: messages

    // A proposal that arrives while another dialog is open is turned down
    // instead of being lost, so the other player is never left waiting.
    private func present(_ alert: ChessAlert, orElse decline: String) {
        if activeAlert == nil && pendingPromotion == nil {
            activeAlert = alert
        } else {
            InternetConnectionManager.shared.sendMessage(decline)
        }
    }

    // Everything a peer sends is checked before it touches the board.
    private func receiveNearbyMessage(_ sender: String, _ raw: String) {
        if sender == myId { return }
        guard let senderSeat = players.firstIndex(where: { $0.id == sender }) else { return }
        guard let msg = ChessWire.parse(raw) else { return }

        if case .reset(let newRound) = msg {
            guard ChessWire.acceptableResetRound(current: roundId, received: newRound) else { return }
            // A game in progress can only be wiped if this player agreed to it
            // (we proposed a new game) - or the game was already over.
            guard gameOver || newGameOfferedByMe else { return }
            roundId = newRound
            newGame()
            return
        }
        if msg.round != roundId || gameOver { return } // stale, or the game is already decided

        let senderIsWhite = senderSeat == ChessWire.whiteSeat(roundId)
        switch msg {
        case .move(_, let received):
            // Must be the sender's turn and a move the rules really allow.
            guard senderSeat == ChessWire.seatToMove(pos, round: roundId) else { return }
            guard let legalMove = ChessWire.validate(pos, received) else { return }
            play(legalMove, fromPeer: true)
            notifyFriendMoved(legalMove)
        case .resign:
            gameOver = true
            resultText = "\(players[senderSeat].name) resigned - you win! \u{1F389}"
            confetti.start()
            updateStatus()
        case .newGameOffer:
            if newGameOfferedByMe {
                // We proposed at the same moment: the host does the reset, the guest waits for it.
                if mySeat == 0 { startNextRound() }
            } else {
                present(.newGame(gameId: gameId), orElse: ChessWire.newGameDecline(roundId))
            }
        case .newGameDecline:
            if newGameOfferedByMe {
                newGameOfferedByMe = false
                showToast("\(friendName) wants to keep playing this game.")
            }
        case .clock(_, let seconds):
            // Only the host decides the clock, and only before the first move.
            guard senderSeat == 0, playedMoves.isEmpty else { return }
            clockSeconds = seconds
            resetClock()
            updateStatus()
        case .timeout:
            // The sender says their own clock ran out. Believe it only if it
            // is their turn and our own count of their time agrees (within a
            // few seconds for network delay).
            guard let c = clock, !playedMoves.isEmpty, pos.whiteToMove == senderIsWhite else { return }
            guard c.remaining(white: senderIsWhite, now: nowMs()) <= timeoutToleranceMs else { return }
            winOnTime()
        case .drawOffer:
            if drawOfferedByMe {
                // We both offered at the same moment: that is an agreement.
                InternetConnectionManager.shared.sendMessage(ChessWire.drawAccept(roundId))
                endDrawAgreed()
            } else {
                present(.drawOffer(gameId: gameId, ply: playedMoves.count), orElse: ChessWire.drawDecline(roundId))
            }
        case .drawAccept:
            if drawOfferedByMe { endDrawAgreed() }
        case .drawDecline:
            if drawOfferedByMe {
                drawOfferedByMe = false
                showToast("\(friendName) declined the draw.")
            }
        case .takebackRequest(_, let ply):
            // Only the sender's own last move can be taken back: the request
            // must name exactly the number of moves played so far, and it
            // must be our turn (the sender has just moved). Anything else
            // crossed a move in the post, so it is turned down.
            if ply == playedMoves.count && pos.whiteToMove != senderIsWhite {
                present(.takeback(gameId: gameId, ply: ply), orElse: ChessWire.takebackDecline(roundId, ply))
            } else {
                InternetConnectionManager.shared.sendMessage(ChessWire.takebackDecline(roundId, ply))
            }
        case .takebackAccept(_, let ply):
            // We asked, and our move is still the last one played.
            if takebackRequestedByMe && ply == playedMoves.count && pos.whiteToMove != myIsWhite {
                takebackRequestedByMe = false
                undoLastMove()
                showToast("\(friendName) accepted - move again.")
            }
        case .takebackDecline:
            if takebackRequestedByMe {
                takebackRequestedByMe = false
                showToast("\(friendName) said no to the takeback.")
            }
        case .reset:
            break
        }
    }
}
