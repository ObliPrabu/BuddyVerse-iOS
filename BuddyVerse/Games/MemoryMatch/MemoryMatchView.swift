import SwiftUI

/// Mirrors MemoryMatchActivity.kt. Flip two cards a turn looking for pairs -
/// vs a bot, two people sharing one phone, or real internet multiplayer with
/// any number of players.
///
/// For real multiplayer, everyone needs to see the EXACT same card layout,
/// so whoever is seat 0 in the room's player list (always the host, since
/// the player list comes straight from OnlineLobbyView in join order)
/// shuffles the board and sends it to everyone else via SETUP:, instead of
/// each phone shuffling independently. Turn order is just a rotating index
/// into that same player list - since the list itself already arrived in
/// the same, agreed-upon order on every phone, there's no separate
/// handshake needed to agree on who goes first.
struct MemoryMatchView: View {
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

    private static let icons = ["\u{1F34E}", "\u{1F34C}", "\u{1F347}", "\u{1F352}", "\u{1F353}", "\u{1F34D}",
                                 "\u{1F34E}", "\u{1F34C}", "\u{1F347}", "\u{1F352}", "\u{1F353}", "\u{1F34D}"]

    // "?" hidden, otherwise shows the icon underneath - mirrors each card
    // Button's .text on Android.
    @State private var cardTexts: [String] = Array(repeating: "?", count: 12)
    @State private var shuffledIcons: [String] = []
    @State private var firstClickedIndex: Int?
    @State private var secondClickedIndex: Int?
    @State private var pairsFound = 0
    @State private var isProcessing = false
    // Whether the grid currently has a real board on screen - false while a
    // nearby non-seat-0 player is waiting for the SETUP: shuffle to arrive.
    @State private var boardReady = false

    // --- vs Bot / local "one phone, two people" mode ---
    @State private var isPlayerTurn = true
    @State private var botMemory: [Int: String] = [:]
    // Local pass-and-play only - no bot to track a shared score against, so
    // each human's tally is credited separately based on whose turn it was
    // when the match was found.
    @State private var p1PairsFound = 0
    @State private var p2PairsFound = 0

    // --- Real device-to-device ("Two Phones") mode, any number of players ---
    @State private var turnIndex = 0
    @State private var scores: [String: Int] = [:]
    @State private var roundId = 0

    @State private var didSetup = false
    @State private var didHandleDisconnect = false
    @State private var toastMessage: String?
    @State private var toastToken = UUID()
    @State private var runToken = UUID()

    private func isMyTurn() -> Bool {
        guard !players.isEmpty else { return false }
        return players[turnIndex % players.count].id == myId
    }

    private var pairsText: String {
        if isNearbyGame {
            return players.map { p in
                let label = p.id == myId ? "You" : p.name
                return "\(label): \(scores[p.id] ?? 0)"
            }.joined(separator: "  |  ")
        }
        if isBotGame { return "Pairs Found: \(pairsFound)/6" }
        return "P1: \(p1PairsFound)  |  P2: \(p2PairsFound)"
    }

    private var statusText: String {
        if isNearbyGame && players.isEmpty { return "Connecting..." }
        if isNearbyGame && isMyTurn() { return "Your Turn" }
        if isNearbyGame { return "\(players[turnIndex % players.count].name)'s Turn" }
        if isBotGame && isPlayerTurn { return "Your Turn" }
        if isBotGame { return "Bot (\(difficulty)) Turn" }
        return isPlayerTurn ? "Player 1's Turn" : "Player 2's Turn"
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFF9800).ignoresSafeArea()

            VStack(spacing: 8) {
                Text(statusText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 10)

                Text(pairsText)
                    .font(.system(size: 16))
                    .foregroundColor(.white)

                ScrollView {
                    if boardReady {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(0..<12, id: \.self) { idx in
                                // Android: Color.LTGRAY (#CCCCCC) hidden, Color.WHITE revealed
                                Button(cardTexts[idx] == "?" ? "?" : cardTexts[idx]) { onCardClicked(idx) }
                                    .frame(minWidth: 72, minHeight: 72)
                                    .font(.system(size: 26))
                                    .background(cardTexts[idx] == "?" ? Color(hex: 0xCCCCCC) : Color.white)
                                    .foregroundColor(.black)
                                    .disabled(isProcessing || cardTexts[idx] != "?")
                            }
                        }
                        .padding(6)
                    } else if isNearbyGame {
                        Text("Waiting for the board to be set up...")
                            .foregroundColor(.white)
                            .padding(.top, 40)
                    }
                }

                // btnResetMemory: match_parent, 50dp, bg white, text #FF9800 bold
                Button("New Game") { onNewGamePressed() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: 0xFF9800))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)

                // btnBackMemory: wrap_content, bg #AADDDDDD, text #333333
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
                    .buttonStyle(.plain)
            }
            .padding(16)

            toastOverlay
        }
        .confettiOverlay(confetti)
        .navigationBarBackButtonHidden(true)
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
            for p in players { scores[p.id] = 0 }
            InternetConnectionManager.shared.setListeners(
                onMessage: { msg in DispatchQueue.main.async { receiveNearbyMessage(msg) } },
                onDisconnected: { DispatchQueue.main.async { handleOpponentDisconnected() } }
            )
            beginNearbyRound()
        } else {
            setupGame()
        }
    }

    private func setupGame() {
        cancelPendingCallbacks()
        botMemory = [:]
        pairsFound = 0
        p1PairsFound = 0
        p2PairsFound = 0
        isPlayerTurn = true
        setupBoard(order: Self.icons.shuffled())
    }

    // Rebuilds the card grid using a specific icon order - used so everyone
    // in the room can share the exact same layout in nearby mode.
    private func setupBoard(order: [String]) {
        shuffledIcons = order
        cardTexts = Array(repeating: "?", count: 12)
        firstClickedIndex = nil
        secondClickedIndex = nil
        isProcessing = false
        boardReady = true
    }

    // Only seat 0 (always the host, since the player list arrives in the
    // same join order on every phone) actually generates the shuffle -
    // everyone else waits for it over the wire so all boards match exactly.
    private func beginNearbyRound() {
        cancelPendingCallbacks()
        pairsFound = 0
        for p in players { scores[p.id] = 0 }
        turnIndex = 0
        if let seat0 = players.first, seat0.id == myId {
            let shuffle = Self.icons.shuffled()
            InternetConnectionManager.shared.sendMessage("\(roundId):SETUP:" + shuffle.joined(separator: ","))
            setupBoard(order: shuffle)
        } else {
            boardReady = false
        }
    }

    // MARK: - Card taps

    // respectTurnGuard defaults to true for real taps. botMove() passes
    // false, because by the time the bot acts isPlayerTurn is already
    // false (that's the whole point of it being the bot's turn) - without
    // this bypass the guard below would silently drop the bot's own taps.
    private func onCardClicked(_ index: Int, respectTurnGuard: Bool = true) {
        guard !isProcessing, cardTexts[index] == "?" else { return }

        if isNearbyGame {
            guard !players.isEmpty, isMyTurn() else { return }
            InternetConnectionManager.shared.sendMessage("\(roundId):REVEAL:\(index)")
            applyReveal(index)
            return
        }

        if respectTurnGuard && isBotGame && !isPlayerTurn { return }
        applyReveal(index)
    }

    private func applyReveal(_ index: Int) {
        revealCard(index)
        if firstClickedIndex == nil {
            firstClickedIndex = index
        } else {
            secondClickedIndex = index
            checkForMatch()
        }
    }

    private func revealCard(_ index: Int) {
        cardTexts[index] = shuffledIcons[index]

        if !isNearbyGame {
            let chance: Double
            switch difficulty {
            case "HARD": chance = 1.0 // 100% memory
            case "MEDIUM": chance = 0.6 // 60% memory
            default: chance = 0.2 // 20% memory
            }
            if Double.random(in: 0..<1) < chance {
                botMemory[index] = shuffledIcons[index]
            }
        }
    }

    private func checkForMatch() {
        isProcessing = true
        guard let first = firstClickedIndex, let second = secondClickedIndex else { return }

        if cardTexts[first] == cardTexts[second] {
            pairsFound += 1
            if isNearbyGame {
                // Credit whoever's turn it was when they found this match -
                // every phone processes the same REVEAL messages in the
                // same order, so this stays in sync everywhere.
                if !players.isEmpty {
                    let turnPlayerId = players[turnIndex % players.count].id
                    scores[turnPlayerId] = (scores[turnPlayerId] ?? 0) + 1
                }
            } else {
                let matchedIcon = cardTexts[first]
                botMemory = botMemory.filter { $0.value != matchedIcon }
                // Pass-and-play only (no bot): credit whichever player's
                // turn it currently is.
                if !isBotGame {
                    if isPlayerTurn { p1PairsFound += 1 } else { p2PairsFound += 1 }
                }
            }

            firstClickedIndex = nil
            secondClickedIndex = nil
            isProcessing = false

            let allPairsFound = isNearbyGame ? (scores.values.reduce(0, +) == 6) : (pairsFound == 6)
            if allPairsFound {
                if isNearbyGame {
                    let topScore = scores.values.max() ?? 0
                    let winners = players.filter { (scores[$0.id] ?? 0) == topScore }
                    let amWinner = winners.contains { $0.id == myId }
                    let message: String
                    if winners.count > 1 {
                        message = "GAME OVER! IT'S A TIE between \(winners.map(\.name).joined(separator: ", "))!"
                    } else if amWinner {
                        message = "GAME OVER! YOU WIN!"
                    } else {
                        message = "GAME OVER! \(winners.first?.name ?? "Someone") WINS!"
                    }
                    showToast(message)
                    // Only the winner(s) see victory confetti - matches the
                    // winner-only pattern used in TicTacToe/Count21.
                    if amWinner && winners.count == 1 { confetti.start() }
                } else {
                    showToast("GAME OVER! YOU MATCHED THEM ALL!")
                    confetti.start()
                }
            } else if isBotGame && !isPlayerTurn {
                runAfterDelay(1.0) { botMove() }
            }
            // Nearby mode: a match means the same player just keeps going.
        } else {
            runAfterDelay(1.0) {
                if let f = firstClickedIndex { cardTexts[f] = "?" }
                if let s = secondClickedIndex { cardTexts[s] = "?" }
                firstClickedIndex = nil
                secondClickedIndex = nil

                if isNearbyGame {
                    if !players.isEmpty { turnIndex = (turnIndex + 1) % players.count }
                } else {
                    isPlayerTurn.toggle()
                }
                isProcessing = false

                if isBotGame && !isPlayerTurn {
                    runAfterDelay(1.0) { botMove() }
                }
            }
        }
    }

    private func botMove() {
        guard pairsFound != 6 else { return }

        var firstIdx = -1
        var secondIdx = -1

        let knownPairs = Dictionary(grouping: botMemory, by: { $0.value }).filter { $0.value.count > 1 }
        if let pair = knownPairs.values.first, pair.count >= 2 {
            firstIdx = pair[0].key
            secondIdx = pair[1].key
        } else {
            let available = (0..<12).filter { cardTexts[$0] == "?" }
            guard let picked = available.randomElement() else { return }
            firstIdx = picked

            // Does the bot remember where the match for this card is?
            let icon = shuffledIcons[firstIdx]
            let matchedIdx = botMemory.first(where: { $0.value == icon && $0.key != firstIdx })?.key
            secondIdx = matchedIdx ?? available.filter { $0 != firstIdx }.randomElement() ?? -1
        }

        guard firstIdx != -1, secondIdx != -1 else { return }
        onCardClicked(firstIdx, respectTurnGuard: false)
        runAfterDelay(0.8) {
            onCardClicked(secondIdx, respectTurnGuard: false)
        }
    }

    // MARK: - Nearby wire protocol

    private func receiveNearbyMessage(_ raw: String) {
        guard let sep = raw.firstIndex(of: ":") else { return }
        guard let msgRound = Int(raw[raw.startIndex..<sep]) else { return }
        let msg = String(raw[raw.index(after: sep)...])

        if msg == "RESET" {
            guard msgRound > roundId else { return }
            roundId = msgRound
            beginNearbyRound()
            return
        }

        guard msgRound == roundId else { return }
        handleNearbyMessage(msg)
    }

    private func handleNearbyMessage(_ msg: String) {
        if msg.hasPrefix("SETUP:") {
            let order = msg.dropFirst("SETUP:".count).split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            // Beyond just the right count, the order must actually be a
            // reshuffle of our own 6-pair icon set - otherwise a malformed
            // payload could strand the board with an unmatchable pair.
            if order.count == 12 && order.sorted() == Self.icons.sorted() {
                setupBoard(order: order)
            }
        } else if msg.hasPrefix("REVEAL:") {
            guard let idx = Int(msg.dropFirst("REVEAL:".count)), (0..<12).contains(idx) else { return }
            // Mirrors the isProcessing guard local taps use, so an
            // out-of-cadence REVEAL: can't sneak a card into play outside
            // the score accounting.
            if !isProcessing && cardTexts[idx] == "?" {
                applyReveal(idx)
            }
        }
    }

    private func handleOpponentDisconnected() {
        guard !didHandleDisconnect else { return }
        didHandleDisconnect = true
        InternetConnectionManager.shared.stop()
        router.push(.opponentDisconnected)
    }

    // MARK: - Reset

    private func onNewGamePressed() {
        if isNearbyGame {
            roundId += 1
            InternetConnectionManager.shared.sendMessage("\(roundId):RESET")
            beginNearbyRound()
        } else {
            setupGame()
        }
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
