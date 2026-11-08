import SwiftUI
import UIKit

/// Mirrors CheckersActivity.kt + CheckersView.kt. Three ways to play: against
/// the computer (you are Red and move first), two people sharing one phone, or
/// two phones over the internet. The rules and the bot are in
/// CheckersEngine.swift and the online message format is in
/// CheckersOnline.swift; this screen connects taps to moves, draws the board
/// and shows who is to move and how the game ended.
///
/// A jump is compulsory, so after you tap a piece only the squares it must or
/// may go to light up. A multi-jump is entered one hop at a time: each tap on a
/// landing square narrows down which complete move you mean, and the move is
/// played when the last hop is chosen.
///
/// Online: colours come from the room's seat order and the round number (see
/// CheckersWire), the player with Black sees the board turned around, and every
/// message from the other phone is checked (sender, turn, exact legal move)
/// before it touches the board.
struct CheckersView: View {
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

    // Everything the screen can ask the player in a dialog. One at a time:
    // SwiftUI only shows a single alert per view.
    private enum CheckersAlert: Identifiable {
        case resign
        case drawOffer(gameId: Int, moves: Int)
        case newGame(gameId: Int)

        var id: String {
            switch self {
            case .resign: return "resign"
            case .drawOffer: return "draw"
            case .newGame: return "newgame"
            }
        }
    }

    @State private var pos = CheckersPosition()
    // How many times each position has occurred this game (the same position three times is a draw).
    @State private var seen: [String: Int] = [:]
    @State private var legal: [CheckersMove] = []
    // The squares chosen so far for the move being entered: [piece, first hop, second hop...].
    @State private var prefix: [Int] = []
    @State private var lastMove: CheckersMove?
    @State private var movesPlayed = 0
    @State private var gameOver = false
    @State private var botThinking = false
    @State private var statusText = "Your move"

    // Bumped on New Game and on exit so a bot that is still thinking about an
    // old game can't move in the new one.
    @State private var gameId = 0

    // --- Online ("Two Phones") mode ---
    @State private var myId: String?
    // Bumped on every new game; tags each message so one still in flight when
    // a new game starts is dropped (see CheckersWire).
    @State private var roundId = 0
    @State private var resultText: String?
    @State private var drawOfferedByMe = false
    @State private var newGameOfferedByMe = false

    @State private var activeAlert: CheckersAlert?
    @State private var didSetup = false
    @State private var didHandleDisconnect = false
    @State private var toastMessage: String?
    @State private var toastToken = UUID()
    @State private var showFeedback = false
    @State private var showReport = false

    private let lightColor = Color(hex: 0xF0DDB5)
    private let darkColor = Color(hex: 0x7A4B2A)

    // Seat 0 is the host, seat 1 the guest - the same order on both phones.
    private var mySeat: Int { players.firstIndex { $0.id == myId } ?? -1 }
    private var myIsRed: Bool { mySeat == CheckersWire.redSeat(roundId) }
    private var boardFlipped: Bool { isNearbyGame && !myIsRed }
    private var friendName: String { players.first { $0.id != myId }?.name ?? "Your friend" }

    private var newGameTitle: String {
        guard isNearbyGame else { return "NEW GAME" }
        if gameOver { return "NEW GAME" }
        return newGameOfferedByMe ? "WAITING FOR ANSWER..." : "PROPOSE NEW GAME"
    }

    private var scoreText: String {
        "Red \(CheckersRules.count(pos, red: true))  -  Black \(CheckersRules.count(pos, red: false))"
    }

    var body: some View {
        ZStack {
            Color(hex: 0x3E2723).ignoresSafeArea()

            VStack(spacing: 0) {
                Text("\u{1F534} Checkers")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)

                Text(statusText)
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: 0xFFEB3B))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                Text(scoreText)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 6)

                boardView

                Button(newGameTitle) { onNewGamePressed() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: 0x3E2723))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if isNearbyGame {
                    // Online games only: resign or offer a draw.
                    HStack(spacing: 6) {
                        actionButton("RESIGN", enabled: !gameOver) { activeAlert = .resign }
                        actionButton("DRAW?", enabled: !gameOver && !drawOfferedByMe) { offerDraw() }
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
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "CHECKERS") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "CHECKERS") }
        .alert(item: $activeAlert) { alert in checkersAlert(alert) }
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

    private func checkersAlert(_ alert: CheckersAlert) -> Alert {
        switch alert {
        case .resign:
            return Alert(
                title: Text("Resign this game?"),
                primaryButton: .destructive(Text("Resign")) { confirmResign() },
                secondaryButton: .cancel(Text("Keep playing"))
            )
        case .drawOffer(let openedGame, let moves):
            return Alert(
                title: Text("Draw offer"),
                message: Text("\(friendName) offers a draw. Do you accept?"),
                primaryButton: .default(Text("Accept")) {
                    // A move, a new game or the game ending since the offer was made cancels it.
                    if gameOver || openedGame != gameId || moves != movesPlayed {
                        showToast("That draw offer has expired.")
                        return
                    }
                    InternetConnectionManager.shared.sendMessage(CheckersWire.drawAccept(roundId))
                    endDrawAgreed()
                },
                secondaryButton: .cancel(Text("Decline")) {
                    InternetConnectionManager.shared.sendMessage(CheckersWire.drawDecline(roundId))
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
                    InternetConnectionManager.shared.sendMessage(CheckersWire.newGameDecline(roundId))
                }
            )
        }
    }

    // MARK: - Board drawing

    private var currentOptions: [CheckersMove] {
        prefix.isEmpty ? [] : legal.filter { $0.path.count > prefix.count && Array($0.path[0..<prefix.count]) == prefix }
    }

    private var targets: Set<Int> { Set(currentOptions.map { $0.path[prefix.count] }) }

    private var boardView: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 8
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { drawRow in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { drawCol in
                            squareView(squareAt(drawRow: drawRow, drawCol: drawCol), cell: cell)
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

    private func squareLabel(_ sq: Int) -> String {
        let piece = pos.board[sq]
        let name = "row \(sq / 8 + 1), column \(sq % 8 + 1)"
        if piece == 0 { return name }
        return "\(name), \(piece > 0 ? "red" : "black") \(Checkers.isKing(piece) ? "king" : "piece")"
    }

    private func squareView(_ sq: Int, cell: CGFloat) -> some View {
        let piece = pos.board[sq]
        let isTarget = targets.contains(sq)
        return ZStack {
            Rectangle().fill(Checkers.isDark(sq) ? darkColor : lightColor)
            if let m = lastMove, sq == m.from || sq == m.to {
                Rectangle().fill(Color(hex: 0xFFEB3B, opacity: 0.4))
            }
            if sq == prefix.first || prefix.dropFirst().contains(sq) {
                Rectangle().fill(Color(hex: 0x4CAF50, opacity: 0.53))
            }
            if piece != 0 {
                pieceView(piece, cell: cell)
            }
            if isTarget {
                Circle().fill(Color(hex: 0x304FFE, opacity: 0.67))
                    .frame(width: cell * 0.32, height: cell * 0.32)
            }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture { onSquareTapped(sq) }
        // One labelled element per square, so VoiceOver can read the board and tests can tap a square by number.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(squareLabel(sq)))
        .accessibilityIdentifier("checkers-sq-\(sq)")
    }

    // A painted disc with a lighter inner ring, and a gold crown on kings.
    private func pieceView(_ piece: Int, cell: CGFloat) -> some View {
        let radius = cell * 0.76
        let red = piece > 0
        return ZStack {
            Circle().fill(Color.black.opacity(0.4)).frame(width: radius, height: radius).offset(y: cell * 0.03)
            Circle().fill(red ? Color(hex: 0xD32F2F) : Color(hex: 0x2B2B2B)).frame(width: radius, height: radius)
            Circle().stroke(red ? Color(hex: 0xFF8A80) : Color(hex: 0x8A8A8A), lineWidth: cell * 0.05)
                .frame(width: radius * 0.72, height: radius * 0.72)
            if Checkers.isKing(piece) {
                Text("\u{265B}\u{FE0E}").font(.system(size: cell * 0.5, weight: .bold)).foregroundColor(Color(hex: 0xFFD54F))
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
        // Checkers online is exactly two players and we must be one of them.
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

    // MARK: - Messages from the other phone

    // Everything a peer sends is checked before it touches the board.
    private func receiveNearbyMessage(_ sender: String, _ raw: String) {
        if sender == myId { return }
        guard let senderSeat = players.firstIndex(where: { $0.id == sender }),
              let msg = CheckersWire.parse(raw) else { return }

        if case .reset(let round) = msg {
            if !CheckersWire.acceptableResetRound(current: roundId, received: round) { return }
            // A game in progress can only be wiped if this player agreed (we proposed a new game), or it was already over.
            if !gameOver && !newGameOfferedByMe { return }
            roundId = round
            newGame()
            return
        }
        if msg.round != roundId || gameOver { return } // stale, or the game is already decided

        switch msg {
        case .move(_, let move):
            if senderSeat != CheckersWire.seatToMove(pos, round: roundId) { return }
            guard let legalMove = CheckersRules.validate(pos, move) else { return }
            play(legalMove, fromPeer: true)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                activeAlert = .newGame(gameId: gameId)
            }
        case .newGameDecline:
            if newGameOfferedByMe {
                newGameOfferedByMe = false
                showToast("\(friendName) wants to keep playing this game.")
            }
        case .drawOffer:
            if drawOfferedByMe {
                // We both offered at the same moment: that is an agreement.
                InternetConnectionManager.shared.sendMessage(CheckersWire.drawAccept(roundId))
                endDrawAgreed()
            } else {
                activeAlert = .drawOffer(gameId: gameId, moves: movesPlayed)
            }
        case .drawAccept:
            if drawOfferedByMe { endDrawAgreed() }
        case .drawDecline:
            if drawOfferedByMe {
                drawOfferedByMe = false
                showToast("\(friendName) declined the draw.")
            }
        case .reset:
            break
        }
    }

    // MARK: - Game flow

    private func onNewGamePressed() {
        if !isNearbyGame {
            newGame()
        } else if gameOver {
            // The game is already decided, so either player may start the next
            // one. A new round swaps the colours.
            startNextRound()
        } else {
            proposeNewGame()
        }
    }

    private func confirmResign() {
        if gameOver { return }
        InternetConnectionManager.shared.sendMessage(CheckersWire.resign(roundId))
        gameOver = true
        resultText = "You resigned"
        updateStatus()
    }

    private func startNextRound() {
        roundId += 1
        InternetConnectionManager.shared.sendMessage(CheckersWire.reset(roundId))
        newGame()
    }

    private func proposeNewGame() {
        if newGameOfferedByMe {
            showToast("Still waiting for \(friendName) to answer.")
            return
        }
        newGameOfferedByMe = true
        InternetConnectionManager.shared.sendMessage(CheckersWire.newGameOffer(roundId))
        showToast("New game proposed - waiting for \(friendName). To end this game yourself, resign or offer a draw.", duration: 3.5)
    }

    private func offerDraw() {
        if gameOver || drawOfferedByMe { return }
        drawOfferedByMe = true
        InternetConnectionManager.shared.sendMessage(CheckersWire.drawOffer(roundId))
        showToast("Draw offered - waiting for \(friendName).")
    }

    private func endDrawAgreed() {
        gameOver = true
        drawOfferedByMe = false
        resultText = "Draw - agreed by both players"
        updateStatus()
    }

    private func newGame() {
        gameId += 1
        pos = CheckersPosition()
        seen = [pos.key(): 1]
        legal = CheckersRules.legalMoves(pos)
        prefix = []
        lastMove = nil
        movesPlayed = 0
        gameOver = false
        botThinking = false
        resultText = nil
        drawOfferedByMe = false
        newGameOfferedByMe = false
        updateStatus()
    }

    private var canMoveNow: Bool {
        !gameOver && !botThinking && !(isBotGame && !pos.redToMove) && !(isNearbyGame && pos.redToMove != myIsRed)
    }

    private func onSquareTapped(_ sq: Int) {
        if !canMoveNow { return }

        // Part-way through a move: is this the next hop?
        if !prefix.isEmpty, currentOptions.contains(where: { $0.path[prefix.count] == sq }) {
            prefix.append(sq)
            if let complete = legal.first(where: { $0.path == prefix }) { play(complete) }
            return
        }
        // Otherwise: choose (or change to) a piece that can move, or clear the selection.
        let piece = pos.board[sq]
        let mine = piece != 0 && Checkers.isRed(piece) == pos.redToMove
        if mine && legal.contains(where: { $0.from == sq }) && sq != prefix.first {
            prefix = [sq]
        } else {
            if mine && !legal.contains(where: { $0.from == sq }) && legal.first?.isCapture == true {
                showToast("You have to jump! Pick a piece that can take one.")
            }
            prefix = []
        }
    }

    private func play(_ move: CheckersMove, fromPeer: Bool = false) {
        // Tag with the round the move belongs to and send before anything else can change it.
        if isNearbyGame && !fromPeer {
            InternetConnectionManager.shared.sendMessage(CheckersWire.move(roundId, move))
        }
        pos = CheckersRules.apply(pos, move)
        movesPlayed += 1
        seen[pos.key(), default: 0] += 1
        lastMove = move
        prefix = []
        legal = CheckersRules.legalMoves(pos)
        // A move settles any open draw offer.
        drawOfferedByMe = false
        updateStatus()
        if !gameOver && isBotGame && !pos.redToMove { startBot() }
    }

    private func startBot() {
        botThinking = true
        statusText = "Bot is thinking..."
        let myGame = gameId
        let snapshot = pos
        let level = difficulty
        DispatchQueue.global(qos: .userInitiated).async {
            let move = CheckersBot.chooseMove(snapshot, difficulty: level)
            DispatchQueue.main.async {
                guard myGame == gameId else { return }
                botThinking = false
                if let move, !gameOver { play(move) } else { updateStatus() }
            }
        }
    }

    private func updateStatus() {
        if let text = resultText {
            gameOver = true
            statusText = text
            return
        }
        let result = CheckersRules.result(pos, repeats: seen[pos.key()] ?? 1)
        if result != .ongoing {
            let alreadyOver = gameOver   // confetti only the first time, not on every later refresh
            gameOver = true
            let redWon = result == .redWins
            let humanWon: Bool
            if result == .draw { humanWon = false }
            else if isNearbyGame { humanWon = redWon == myIsRed }
            else if isBotGame { humanWon = redWon }
            else { humanWon = true }
            if result == .draw {
                statusText = (movesPlayed > 0 && pos.quietPlies >= Checkers.drawPlies)
                    ? "Draw - 40 moves each with no capture or man move" : "Draw - the same position three times"
            } else if isNearbyGame {
                statusText = humanWon ? "You win! \u{1F389}" : "\(friendName) wins"
            } else if isBotGame {
                statusText = redWon ? "You win! \u{1F389}" : "The bot wins"
            } else {
                statusText = "\(redWon ? "Red" : "Black") wins! \u{1F389}"
            }
            if humanWon && !alreadyOver { confetti.start() }
            return
        }
        if botThinking { return }
        let side = pos.redToMove ? "Red" : "Black"
        let mustJump = legal.first?.isCapture == true
        let who: String
        if isNearbyGame { who = pos.redToMove == myIsRed ? "Your move" : "\(friendName)'s move" }
        else if isBotGame { who = "Your move" }
        else { who = "\(side) to move" }
        statusText = (mustJump && canMoveNow) ? "\(who) - you must jump!" : who
    }
}
