import SwiftUI

/// Mirrors TicTacToeActivity.kt. Three ways to play: vs a bot, two people
/// sharing one phone (pass-and-play), or real internet multiplayer via
/// InternetConnectionManager. The wire protocol - "<round>:HELLO:<token>",
/// "<round>:MOVE:<idx>", "<round>:RESET" - is ported byte-for-byte,
/// including the round-id tagging that stops a stale MOVE (e.g. one sent
/// right as the other phone hits Reset) from ever landing on the wrong
/// round, and the fix where a *winning* move captures roundId into a local
/// before applying it, since applying it can bump roundId as part of
/// starting the next round.
struct TicTacToeView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    private let difficulty: String
    private let isBotGame: Bool
    private let isNearbyGame: Bool

    init(selection: GameSelection) {
        self.difficulty = selection.difficulty ?? "EASY"
        self.isBotGame = selection.isBot
        self.isNearbyGame = selection.isNearby
    }

    // "" empty, "X" or "O" - mirrors each Button's .text in the Kotlin grid.
    @State private var board: [String] = Array(repeating: "", count: 9)
    @State private var roundCount = 0

    // Bumped every time a new round starts (manual Reset, or a win/draw).
    // Every nearby message is tagged with the round it was sent for, so a
    // message still in flight when a Reset happens can be told apart from
    // the fresh round and dropped instead of misapplied to it.
    @State private var roundId = 0

    // --- vs Bot / local "one phone, two people" mode ---
    @State private var isPlayer1Turn = true
    // Whoever didn't go first last round goes first this round.
    @State private var player1StartsNext = true

    // --- Real device-to-device ("Two Phones") mode ---
    @State private var roleAssigned = false
    @State private var amX = false
    @State private var xToMove = true
    @State private var myToken: Int64 = 0
    // Which symbol goes first next round - swaps after every finished game.
    @State private var xStartsNext = true

    @State private var didSetup = false
    @State private var didHandleDisconnect = false
    @State private var toastMessage: String?
    @State private var toastToken = UUID()
    @State private var showFeedback = false
    @State private var showReport = false
    // Cancels every pending delayed bot move at once, the same way
    // handler.removeCallbacksAndMessages(null) does on Android.
    @State private var runToken = UUID()

    private static let winLines: [[Int]] = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8],
        [0, 3, 6], [1, 4, 7], [2, 5, 8],
        [0, 4, 8], [2, 4, 6]
    ]

    private var statusText: String {
        if isNearbyGame {
            if !roleAssigned { return "Connecting..." }
            return xToMove == amX ? "Your Turn (\(amX ? "X" : "O"))" : "Opponent's Turn"
        } else if isBotGame {
            return isPlayer1Turn ? "Your Turn (X)" : "Bot (\(difficulty)) Turn"
        } else {
            return isPlayer1Turn ? "Player 1's Turn (X)" : "Player 2's Turn (O)"
        }
    }

    var body: some View {
        ZStack {
            // activity_tic_tac_toe.xml: root LinearLayout android:background="#2196F3"
            Color(hex: 0x2196F3).ignoresSafeArea()

            VStack(spacing: 0) {
                Text(statusText)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 30)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(80), spacing: 8), count: 3), spacing: 8) {
                    ForEach(0..<9, id: \.self) { idx in
                        // Widget.MaterialComponents.Button.OutlinedButton, backgroundTint #44FFFFFF
                        //
                        // Deliberately a Text + onTapGesture, not a Button:
                        // a plain-styled Button here was silently swallowing
                        // taps on-device (board never updated in any mode -
                        // bot, pass-and-play, or online - even though the
                        // exact same handler works fine when called from
                        // Reset/Back, which aren't inside this LazyVGrid).
                        // contentShape makes the *entire* 80x80 frame
                        // tappable, not just wherever the (often-empty)
                        // text glyph itself renders.
                        Text(board[idx])
                            .frame(width: 80, height: 80)
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .background(Color.white.opacity(0x44 / 255.0))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { onButtonClicked(idx) }
                    }
                }
                .padding(.bottom, 30)

                // btnResetTTT: match_parent width, 60dp height, white bg, blue bold text
                Button("Reset Game") { onResetPressed() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: 0x2196F3))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.bottom, 10)

                // btnBackTTT: wrap_content, backgroundTint #AADDDDDD, textColor #333333
                HStack(spacing: 10) {
                    Button("Back") { router.pop() }
                    Button("Home") { router.popToRoot() }
                }
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x333333))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                HStack(spacing: 10) {
                    Button("Feedback") { showFeedback = true }
                    Button("Report") { showReport = true }
                }
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x333333))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 10)
            }
            .buttonStyle(.plain)
            .padding(20)

            toastOverlay
        }
        .confettiOverlay(confetti)
        .navigationBarBackButtonHidden(true)
        .onAppear { setupIfNeeded() }
        .onDisappear {
            if isNearbyGame { InternetConnectionManager.shared.stop() }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "TICTACTOE") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "TICTACTOE") }
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

    // MARK: - Setup

    private func setupIfNeeded() {
        guard !didSetup else { return }
        didSetup = true

        if isNearbyGame {
            // Assign our token before attaching listeners: setListeners()
            // synchronously replays any buffered HELLO the opponent already
            // sent, and that replay needs to see the real token, not the 0
            // default it'd see if this were assigned afterward.
            myToken = Int64.random(in: Int64.min...Int64.max)
            InternetConnectionManager.shared.setListeners(
                onMessage: { msg in DispatchQueue.main.async { receiveNearbyMessage(msg) } },
                onDisconnected: { DispatchQueue.main.async { handleOpponentDisconnected() } }
            )
            // Always broadcast our own token, even if the buffered replay
            // above already resolved our role from the opponent's HELLO -
            // they still need OUR token to resolve theirs. Skipping this
            // whenever we already knew our role left the other phone stuck
            // on "Connecting..." forever, since nobody ever told them who we are.
            InternetConnectionManager.shared.sendMessage("\(roundId):HELLO:\(myToken)")
        }
    }

    // MARK: - Local taps

    private func onButtonClicked(_ idx: Int) {
        guard board[idx].isEmpty else { return }

        if isNearbyGame {
            guard roleAssigned, xToMove == amX else { return }
            // Capture the round this move is actually being made in before
            // applyMove() runs - a winning move flows through
            // checkForWin() -> playerWinNearby(), which bumps roundId as
            // part of starting the next round.
            let sentRoundId = roundId
            applyMove(idx, wasXMove: xToMove)
            InternetConnectionManager.shared.sendMessage("\(sentRoundId):MOVE:\(idx)")
        } else if isBotGame {
            guard isPlayer1Turn else { return }
            board[idx] = "X"
            roundCount += 1
            if checkForWin() {
                playerWin("X")
            } else if roundCount == 9 {
                draw()
            } else {
                isPlayer1Turn = false
                scheduleBotMove()
            }
        } else {
            board[idx] = isPlayer1Turn ? "X" : "O"
            roundCount += 1
            if checkForWin() {
                playerWin(isPlayer1Turn ? "X" : "O")
            } else if roundCount == 9 {
                draw()
            } else {
                isPlayer1Turn.toggle()
            }
        }
    }

    private func scheduleBotMove() {
        runAfterDelay(0.6) { botMove() }
    }

    private func botMove() {
        guard roundCount < 9 else { return }

        let moveIndex: Int
        switch difficulty {
        case "HARD": moveIndex = getBestMove()
        case "MEDIUM": moveIndex = getMediumMove()
        default: moveIndex = getRandomMove()
        }
        guard moveIndex != -1 else { return }

        board[moveIndex] = "O"
        roundCount += 1
        if checkForWin() {
            playerWin("O")
        } else if roundCount == 9 {
            draw()
        } else {
            isPlayer1Turn = true
        }
    }

    private func getRandomMove() -> Int {
        let available = (0..<9).filter { board[$0].isEmpty }
        return available.randomElement() ?? -1
    }

    private func getMediumMove() -> Int {
        let winMove = findWinningMove("O")
        if winMove != -1 { return winMove }
        let blockMove = findWinningMove("X")
        if blockMove != -1 { return blockMove }
        return getRandomMove()
    }

    // HARD difficulty: a full minimax search rather than a heuristic chain,
    // so it's provably optimal (it can always see a human "fork" - two
    // simultaneous winning threats - coming, unlike a one-ply heuristic).
    // Runs on a scratch copy of the board, never touching @State mid-search,
    // since mutating @State on every one of the (small but nontrivial)
    // number of recursive steps would trigger a SwiftUI re-render each time.
    private func getBestMove() -> Int {
        var scratch = board
        var bestScore = Int.min
        var bestMove = -1
        for i in 0..<9 where scratch[i].isEmpty {
            scratch[i] = "O"
            let score = minimax(&scratch, depth: 1, isMaximizing: false)
            scratch[i] = ""
            if score > bestScore {
                bestScore = score
                bestMove = i
            }
        }
        return bestMove
    }

    // Standard minimax: the bot (O) picks the move that maximizes this
    // score, the human (X) is assumed to play the move that minimizes it.
    // Scores are offset by depth so a win found sooner scores higher than
    // one found later.
    private func minimax(_ cells: inout [String], depth: Int, isMaximizing: Bool) -> Int {
        if checkWinFor(cells, "O") { return 10 - depth }
        if checkWinFor(cells, "X") { return depth - 10 }
        if !cells.contains("") { return 0 } // draw

        if isMaximizing {
            var best = Int.min
            for i in 0..<9 where cells[i].isEmpty {
                cells[i] = "O"
                best = max(best, minimax(&cells, depth: depth + 1, isMaximizing: false))
                cells[i] = ""
            }
            return best
        } else {
            var best = Int.max
            for i in 0..<9 where cells[i].isEmpty {
                cells[i] = "X"
                best = min(best, minimax(&cells, depth: depth + 1, isMaximizing: true))
                cells[i] = ""
            }
            return best
        }
    }

    private func checkWinFor(_ cells: [String], _ player: String) -> Bool {
        for line in Self.winLines {
            if cells[line[0]] == player && cells[line[1]] == player && cells[line[2]] == player { return true }
        }
        return false
    }

    private func findWinningMove(_ player: String) -> Int {
        var scratch = board
        for i in 0..<9 where scratch[i].isEmpty {
            scratch[i] = player
            let wins = checkForWin(scratch)
            scratch[i] = ""
            if wins { return i }
        }
        return -1
    }

    private func checkForWin() -> Bool { checkForWin(board) }

    private func checkForWin(_ cells: [String]) -> Bool {
        for line in Self.winLines {
            let a = cells[line[0]]
            if !a.isEmpty && a == cells[line[1]] && a == cells[line[2]] { return true }
        }
        return false
    }

    // MARK: - Nearby wire protocol

    private func applyMove(_ idx: Int, wasXMove: Bool) {
        board[idx] = wasXMove ? "X" : "O"
        roundCount += 1
        if checkForWin() {
            playerWinNearby(wasXMove)
        } else if roundCount == 9 {
            draw()
        } else {
            xToMove.toggle()
        }
    }

    // Every nearby message arrives as "<round>:<rest>" - this strips that
    // prefix off, checks it against the round we're currently on, and only
    // then hands the real message to handleNearbyMessage. RESET is the one
    // exception: it's what moves us into a new round, so it's fine even
    // when it doesn't match our current round yet.
    private func receiveNearbyMessage(_ raw: String) {
        guard let sep = raw.firstIndex(of: ":") else { return }
        guard let msgRound = Int(raw[raw.startIndex..<sep]) else { return }
        let msg = String(raw[raw.index(after: sep)...])

        if msg == "RESET" {
            guard msgRound > roundId else { return } // duplicate/out-of-order, already applied
            roundId = msgRound
            resetGame()
            return
        }

        guard msgRound == roundId else { return } // stale - belongs to a round we've already left
        handleNearbyMessage(msg)
    }

    private func handleNearbyMessage(_ msg: String) {
        if msg.hasPrefix("HELLO:") {
            guard let theirToken = Int64(msg.dropFirst("HELLO:".count)) else { return }
            if theirToken == myToken {
                // Extremely unlikely tie - pick again and resend.
                myToken = Int64.random(in: Int64.min...Int64.max)
                InternetConnectionManager.shared.sendMessage("\(roundId):HELLO:\(myToken)")
                return
            }
            amX = myToken > theirToken
            roleAssigned = true
            xToMove = true
        } else if msg.hasPrefix("MOVE:") {
            guard let idx = Int(msg.dropFirst("MOVE:".count)), (0..<9).contains(idx), board[idx].isEmpty else { return }
            applyMove(idx, wasXMove: xToMove)
        }
    }

    private func handleOpponentDisconnected() {
        guard !didHandleDisconnect else { return }
        didHandleDisconnect = true
        // Kotlin's onDestroy (triggered by finish()) is what actually calls
        // InternetConnectionManager.stop() here - SwiftUI's push-based
        // NavigationStack doesn't tear this view down just because another
        // one is pushed on top, so stop explicitly right here to get the
        // same net effect.
        InternetConnectionManager.shared.stop()
        router.push(.opponentDisconnected)
    }

    // MARK: - Round outcomes

    private func playerWin(_ p: String) {
        showToast(isBotGame && p == "O" ? "Bot Wins!" : "Player \(p) Wins!")
        confetti.start()
        player1StartsNext.toggle()
        resetGame()
    }

    private func playerWinNearby(_ xWon: Bool) {
        let iWon = xWon == amX
        showToast(iWon ? "You Win! \u{1F389}" : "Opponent Wins!")
        if iWon { confetti.start() }
        xStartsNext.toggle()
        // Both phones process the exact same MOVE stream in the same order,
        // so they reach this win independently but at the same logical
        // point - bumping the round here keeps both phones' round numbers
        // in sync automatically, with no extra message needed.
        roundId += 1
        resetGame()
    }

    private func draw() {
        showToast("Draw!")
        if isNearbyGame {
            xStartsNext.toggle()
            roundId += 1
        } else {
            player1StartsNext.toggle()
        }
        resetGame()
    }

    // Just wipes the board - does NOT swap who starts next. That's decided
    // separately, at the moment a round actually finishes, so a manual
    // Reset mid-game doesn't unfairly swap the starting turn.
    private func resetGame() {
        cancelPendingCallbacks()
        board = Array(repeating: "", count: 9)
        roundCount = 0
        if isNearbyGame {
            xToMove = xStartsNext
        } else {
            isPlayer1Turn = player1StartsNext
            // If the bot is the one designated to start this round, kick it
            // off manually - nothing else will call botMove() otherwise.
            if isBotGame && !isPlayer1Turn {
                scheduleBotMove()
            }
        }
    }

    private func onResetPressed() {
        if isNearbyGame {
            roundId += 1
            InternetConnectionManager.shared.sendMessage("\(roundId):RESET")
        }
        resetGame()
    }

    // MARK: - Small helpers

    private func runAfterDelay(_ seconds: Double, action: @escaping () -> Void) {
        let token = runToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if token == runToken { action() }
        }
    }

    private func cancelPendingCallbacks() {
        runToken = UUID()
    }

    private func showToast(_ text: String, duration: Double = 2.0) {
        toastMessage = text
        let token = UUID()
        toastToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if toastToken == token { toastMessage = nil }
        }
    }
}

fileprivate extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
