import SwiftUI

/// Mirrors CountTo21Activity.kt. Take turns adding 1, 2, or 3 - whoever is
/// forced to say 21 loses. Either vs a bot, two people sharing one phone, or
/// real internet multiplayer over InternetConnectionManager with any number
/// of players. Wire protocol ("<round>:MOVE:<num>", "<round>:RESET") ported
/// byte-for-byte, including the round-id-capture fix on a game-ending move
/// (applyMove()'s game-over branch bumps roundId before returning, so the
/// outgoing MOVE has to be tagged with the round it was actually sent in,
/// not the round that's just starting). The old per-round HELLO token
/// handshake is gone - since the full player list (in a fixed, agreed-upon
/// order) now arrives up front via GameSelection.players, turn order is just
/// a rotating index into that list.
struct CountTo21View: View {
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    private let difficulty: String
    private let isBotGame: Bool
    private let isNearbyGame: Bool
    private let players: [Player]
    private let myId: String?

    init(selection: GameSelection) {
        self.difficulty = selection.difficulty ?? "EASY"
        self.isBotGame = selection.isBot
        self.isNearbyGame = selection.isNearby
        self.players = selection.players ?? []
        self.myId = InternetConnectionManager.shared.myPlayerId()
    }

    @State private var currentCount = 0

    // --- vs Bot mode ---
    @State private var isPlayerTurn = true

    // --- Real device-to-device ("Two Phones") mode, any number of players ---
    @State private var turnIndex = 0

    // Who starts the *next* round - alternates every time a round actually
    // finishes, so whoever didn't go first last round goes first this time.
    // starterIsPlayerOne covers bot mode/local pass-and-play; starterIndex
    // covers nearby multiplayer, rotating through every seat instead of just
    // flipping between two. Every phone in a nearby game advances
    // starterIndex at the same logical point (inside applyMove(), which
    // every phone runs identically for every move in the same order), so
    // they stay in sync with no extra message needed - same trick roundId uses.
    @State private var starterIsPlayerOne = true
    @State private var starterIndex = 0
    @State private var roundId = 0

    @State private var didSetup = false
    @State private var didHandleDisconnect = false
    @State private var showTrickAlert = false
    @State private var toastMessage: String?
    @State private var toastToken = UUID()
    @State private var runToken = UUID()

    private func isMyTurn() -> Bool {
        guard !players.isEmpty else { return false }
        return players[turnIndex % players.count].id == myId
    }

    private var turnStatusText: String {
        if isNearbyGame {
            if players.isEmpty { return "Connecting..." }
            return isMyTurn() ? "Your Turn" : "\(players[turnIndex % players.count].name)'s Turn"
        } else if isBotGame {
            return isPlayerTurn ? "Your Turn" : "Bot (\(difficulty)) Turn"
        } else {
            return isPlayerTurn ? "Player 1's Turn" : "Player 2's Turn"
        }
    }

    private var buttonsEnabled: Bool {
        if isNearbyGame { return !players.isEmpty && isMyTurn() }
        if isBotGame { return isPlayerTurn }
        return true
    }

    var body: some View {
        ZStack {
            Color(hex: 0x1A237E).ignoresSafeArea()

            VStack(spacing: 10) {
                Text("Count to 21")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text(turnStatusText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFEB3B))

                Text("If you reach 21, you lose!")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: 0xFFCDD2))
                    .padding(.bottom, 20)

                Text("Current Count: \(currentCount)")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .padding(.bottom, 12)

                HStack(spacing: 10) {
                    ForEach(1...3, id: \.self) { n in
                        Button("+\(n)") { playerMove(n) }
                            .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0x4CAF50)))
                            .foregroundColor(.white)
                            .disabled(!buttonsEnabled)
                    }
                }

                Button("Show the trick?") { showTrickAlert = true }
                    .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0xFFC107)))
                    .foregroundColor(Color(hex: 0x1A237E))
                    .padding(.top, 24)

                // btnReset: backgroundTint #757575, no textColor override (white default)
                Button("Reset Game") { onResetPressed() }
                    .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0x757575)))
                    .foregroundColor(.white)

                // btnBackWelcome: backgroundTint #BDBDBD, textColor #333
                Button("Back to Welcome") { router.pop() }
                    .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0xBDBDBD)))
                    .foregroundColor(Color(hex: 0x333333))
            }
            .padding(20)

            toastOverlay
        }
        .confettiOverlay(confetti)
        .navigationBarBackButtonHidden(true)
        // The actions:/message: alert overload (and Button's `role:`) needs
        // iOS 15 - this is the Alert(title:message:dismissButton:) form.
        .alert(isPresented: $showTrickAlert) {
            Alert(
                title: Text("The Secret Trick"),
                message: Text("""
                Try to be the one to say 4, 8, 12, 16, or 20 - those are the \
                "safe" numbers. If you say one, your opponent can't reach the \
                next safe number no matter what they add (1, 2, or 3), which \
                means YOU always can.

                Keep landing on safe numbers all the way up, and your opponent \
                gets forced into saying 21 every time!
                """),
                dismissButton: .default(Text("Got it!"))
            )
        }
        .onAppear { setupIfNeeded() }
        .onDisappear {
            if isNearbyGame { InternetConnectionManager.shared.stop() }
        }
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
                    .multilineTextAlignment(.center)
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
            turnIndex = 0
            starterIndex = 0
            InternetConnectionManager.shared.setListeners(
                onMessage: { msg in DispatchQueue.main.async { receiveNearbyMessage(msg) } },
                onDisconnected: { DispatchQueue.main.async { handleOpponentDisconnected() } }
            )
        }
    }

    // MARK: - Moves

    private func playerMove(_ num: Int) {
        if isNearbyGame {
            guard !players.isEmpty, isMyTurn() else { return }
            // Capture the round this move is actually being made in before
            // applyMove() runs - if this move reaches 21, applyMove()'s
            // game-over branch bumps roundId for the next round before
            // returning.
            let sentRoundId = roundId
            applyMove(num)
            InternetConnectionManager.shared.sendMessage("\(sentRoundId):MOVE:\(num)")
            return
        }

        if isBotGame && !isPlayerTurn { return }

        currentCount += num

        if currentCount >= 21 {
            let message = isBotGame
                ? "You reached \(currentCount)! YOU LOSE!"
                : "\(isPlayerTurn ? "Player 1" : "Player 2") reached \(currentCount) and loses!"
            showToast(message)
            starterIsPlayerOne.toggle()
            resetGame()
        } else {
            isPlayerTurn.toggle()
            if isBotGame && !isPlayerTurn {
                runAfterDelay(1.0) { botMove() }
            }
        }
    }

    private func applyMove(_ num: Int) {
        currentCount += num

        if currentCount >= 21 {
            let loser = players[turnIndex % players.count]
            let iLost = loser.id == myId
            showToast(iLost ? "You reached \(currentCount)! YOU LOSE!" : "\(loser.name) reached \(currentCount)! YOU WIN!")
            if !iLost { confetti.start() }
            // Every phone processes the exact same MOVE stream in the same
            // order, so they reach this ending independently but at the
            // same logical point - advancing the round/starter here keeps
            // everyone's state in sync automatically.
            if isNearbyGame {
                roundId += 1
                if !players.isEmpty { starterIndex = (starterIndex + 1) % players.count }
            }
            resetGame()
        } else {
            if !players.isEmpty { turnIndex = (turnIndex + 1) % players.count }
        }
    }

    private func botMove() {
        let move: Int
        switch difficulty {
        case "HARD":
            // Perfect AI: tries to reach multiples of 4 (4, 8, 12, 16, 20).
            move = currentCount % 4 == 0 ? Int.random(in: 1...3) : 4 - (currentCount % 4)
        case "MEDIUM":
            // 50% chance to play perfectly, 50% random.
            if Double.random(in: 0..<1) > 0.5 {
                move = currentCount % 4 == 0 ? Int.random(in: 1...3) : 4 - (currentCount % 4)
            } else {
                move = Int.random(in: 1...3)
            }
        default:
            move = Int.random(in: 1...3) // EASY: completely random
        }

        currentCount += move
        showToast("Bot (\(difficulty)) added \(move)")

        if currentCount >= 21 {
            showToast("Bot reached \(currentCount)! YOU WIN!")
            confetti.start()
            starterIsPlayerOne.toggle()
            resetGame()
        } else {
            isPlayerTurn = true
        }
    }

    // MARK: - Nearby wire protocol

    // Every nearby message arrives as "<round>:<rest>" - see the matching
    // comment in TicTacToeView for why RESET is the one exception allowed
    // through even when it doesn't match our current round yet.
    private func receiveNearbyMessage(_ raw: String) {
        guard let sep = raw.firstIndex(of: ":") else { return }
        guard let msgRound = Int(raw[raw.startIndex..<sep]) else { return }
        let msg = String(raw[raw.index(after: sep)...])

        if msg == "RESET" {
            guard msgRound > roundId else { return }
            roundId = msgRound
            resetGame()
            return
        }

        guard msgRound == roundId else { return }
        handleNearbyMessage(msg)
    }

    private func handleNearbyMessage(_ msg: String) {
        if msg.hasPrefix("MOVE:") {
            guard let num = Int(msg.dropFirst("MOVE:".count)) else { return }
            // Mirrors the bounds-check the other multiplayer games apply to
            // their incoming messages - the 1-3 rule is otherwise only
            // enforced on the sending side.
            guard (1...3).contains(num) else { return }
            if !isMyTurn() { applyMove(num) }
        }
    }

    private func handleOpponentDisconnected() {
        guard !didHandleDisconnect else { return }
        didHandleDisconnect = true
        InternetConnectionManager.shared.stop()
        router.push(.opponentDisconnected)
    }

    // MARK: - Reset

    private func resetGame() {
        cancelPendingCallbacks()
        currentCount = 0
        if isNearbyGame {
            turnIndex = starterIndex
        } else {
            isPlayerTurn = starterIsPlayerOne
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
