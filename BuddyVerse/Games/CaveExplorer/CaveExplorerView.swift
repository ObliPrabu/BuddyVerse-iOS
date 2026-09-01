import SwiftUI

/// Mirrors CaveExplorerActivity. Unlike Desert Trek's single "walk forward"
/// mash, each turn here is a real trade-off between two buttons: push deeper
/// for progress at the cost of a lot of torch light, or stop to rest and
/// relight (regain some light, but make no depth progress that turn).
/// There's one shared torch light/depth pool everyone takes turns
/// contributing to (vs a bot, two people passing one phone, or now any
/// number of people online) - whoever's turn empties the shared torch light
/// runs out of light and loses; everyone else wins.
///
/// Real multiplayer here is built from scratch (unlike Tic-Tac-Toe/Hangman/
/// Memory/Count21, which already had it) - since there's real randomness
/// every turn (how much depth/torch a choice costs), whoever's turn it is
/// resolves that randomness locally and broadcasts the resolved numbers, and
/// everyone else just applies them - nobody re-rolls their own copy, so
/// every phone ends up with the exact same torch/depth no matter whose turn
/// it was.
struct CaveExplorerView: View {
    @StateObject private var vm: CaveExplorerViewModel
    @EnvironmentObject private var router: Router

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: CaveExplorerViewModel(
            isBot: selection.isBot,
            difficulty: selection.difficulty ?? "EASY",
            isNearby: selection.isNearby,
            players: selection.players ?? []
        ))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Cave Explorer")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Text(vm.turnLabel)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 8)

            Text("Torch Light: \(max(vm.torchLight, 0))%")
                .font(.system(size: 20))
                .foregroundColor(Color(hex: 0xFFEB3B))

            Text("Depth: \(vm.depth)m")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(.bottom, 20)

            Text("🕯️")
                .font(.system(size: 60))
                .frame(width: 100, height: 100)
                .padding(.bottom, 12)

            Text(vm.turnMessage)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(minHeight: 40)
                .padding(.horizontal)

            Spacer(minLength: 4)

            HStack(spacing: 10) {
                Button {
                    vm.takeTurn(explore: true)
                } label: {
                    Text("🔦 Explore")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.white)
                .foregroundColor(Color(hex: 0x3E2723))

                Button {
                    vm.takeTurn(explore: false)
                } label: {
                    Text("🕯️ Rest")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.white)
                .foregroundColor(Color(hex: 0x3E2723))
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(!vm.buttonsEnabled)
            .opacity(vm.buttonsEnabled ? 1 : 0.5)
            .padding(.bottom, 20)

            HStack(spacing: 10) {
                Button("Back to Menu") { router.pop() }
                Button("Home") { router.popToRoot() }
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: 0xDDDDDD, opacity: 0.67))
            .foregroundColor(Color(hex: 0x333333))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x3E2723).ignoresSafeArea())
        .navigationTitle("Cave Explorer")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $vm.roundOver) { (info: CaveRoundOverInfo) in
            Alert(title: Text("Round Over"), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
        .onChange(of: vm.isDisconnected) { disconnected in
            if disconnected { router.push(.opponentDisconnected) }
        }
        .onAppear {
            vm.turnMessage = "Explore for progress, or Rest to relight your torch!"
            vm.startIfNeeded()
        }
        .onDisappear { vm.stop() }
    }
}

@MainActor
final class CaveExplorerViewModel: ObservableObject {
    @Published var torchLight = 100
    @Published var depth = 0
    @Published var isPlayerTurn = true
    @Published var turnMessage = ""
    @Published var roundOver: CaveRoundOverInfo?
    @Published var isDisconnected = false

    let isBot: Bool
    let difficulty: String
    private var isStopped = false

    // --- Real device-to-device ("Two Phones") mode, any number of players ---
    let isNearby: Bool
    let players: [Player]
    private let myId: String?
    @Published var turnIndex = 0
    private var roundId = 0
    private var didSetup = false

    init(isBot: Bool, difficulty: String, isNearby: Bool = false, players: [Player] = []) {
        self.isBot = isBot
        self.difficulty = difficulty
        self.isNearby = isNearby
        self.players = players
        self.myId = InternetConnectionManager.shared.myPlayerId()
    }

    func startIfNeeded() {
        guard !didSetup else { return }
        didSetup = true
        guard isNearby else { return }
        turnIndex = 0
        InternetConnectionManager.shared.setListeners(
            onMessage: { [weak self] msg in DispatchQueue.main.async { self?.receiveNearbyMessage(msg) } },
            onDisconnected: { [weak self] in
                DispatchQueue.main.async {
                    guard let self, !self.isStopped else { return }
                    self.isStopped = true
                    InternetConnectionManager.shared.stop()
                    self.isDisconnected = true
                }
            }
        )
    }

    private func isMyTurn() -> Bool {
        guard !players.isEmpty else { return false }
        return players[turnIndex % players.count].id == myId
    }

    var turnLabel: String {
        if isNearby {
            if players.isEmpty { return "Connecting..." }
            return isMyTurn() ? "Your Turn" : "\(players[turnIndex % players.count].name)'s Turn"
        } else if isBot {
            return isPlayerTurn ? "Your Turn" : "Bot (\(difficulty)) Turn"
        } else {
            return isPlayerTurn ? "Player 1's Turn" : "Player 2's Turn"
        }
    }

    // Local pass-and-play (no bot) keeps the same two buttons live for
    // whichever player's turn it currently is, alternating every move.
    var buttonsEnabled: Bool {
        if isNearby { return !players.isEmpty && isMyTurn() }
        return isBot ? isPlayerTurn : true
    }

    func takeTurn(explore: Bool) {
        guard buttonsEnabled else { return }

        if isNearby {
            let depthGained = explore ? Int.random(in: 5..<16) : 0
            let torchChange = explore ? -Int.random(in: 10..<26) : Int.random(in: 10..<21)
            let sentRoundId = roundId
            guard let actorId = myId else { return }
            applyNearbyTurn(actorId: actorId, explore: explore, depthGained: depthGained, torchChange: torchChange)
            InternetConnectionManager.shared.sendMessage(
                "\(sentRoundId):TURN:\(actorId):\(explore ? "EXPLORE" : "REST"):\(depthGained):\(torchChange)"
            )
            return
        }

        takeTurn(isPlayer: isPlayerTurn, explore: explore)
    }

    // Applies one resolved turn (from either this device or a message from
    // someone else's) to the shared torch/depth pool. Every phone in the
    // room calls this with the exact same numbers for the exact same turn,
    // so they all end up in perfect agreement about the shared state.
    private func applyNearbyTurn(actorId: String, explore: Bool, depthGained: Int, torchChange: Int) {
        let actorName = players.first(where: { $0.id == actorId })?.name ?? "Someone"
        depth += depthGained
        torchLight = min(torchLight + torchChange, 100)

        if explore {
            turnMessage = "\(actorName) explored \(depthGained)m deeper and lost \(-torchChange)% torch light!"
        } else {
            turnMessage = "\(actorName) rested and relit \(torchChange)% torch light."
        }

        if torchLight <= 0 {
            let iRanOut = actorId == myId
            turnMessage = iRanOut
                ? "You ran out of light at \(depth)m! YOU LOSE!"
                : "\(actorName) ran out of light at \(depth)m and loses! Everyone else wins! 🏆"
            torchLight = 100
            depth = 0
            let actorIndex = players.firstIndex(where: { $0.id == actorId })
            turnIndex = actorIndex.map { ($0 + 1) % players.count } ?? 0
        } else {
            turnIndex = players.isEmpty ? 0 : (turnIndex + 1) % players.count
        }
    }

    private func receiveNearbyMessage(_ raw: String) {
        guard let sep = raw.firstIndex(of: ":") else { return }
        guard let msgRound = Int(raw[raw.startIndex..<sep]) else { return }
        let msg = String(raw[raw.index(after: sep)...])

        guard msgRound == roundId else { return } // stale - belongs to a round we've already left
        guard msg.hasPrefix("TURN:") else { return }

        let parts = msg.dropFirst("TURN:".count).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else { return }
        let actorId = parts[0]
        guard actorId != myId else { return } // our own move, already applied locally
        let explore = parts[1] == "EXPLORE"
        guard let depthGained = Int(parts[2]), let torchChange = Int(parts[3]) else { return }
        applyNearbyTurn(actorId: actorId, explore: explore, depthGained: depthGained, torchChange: torchChange)
    }

    private func takeTurn(isPlayer: Bool, explore: Bool) {
        let depthGained: Int
        let torchChange: Int
        if explore {
            depthGained = Int.random(in: 5..<16)
            torchChange = -Int.random(in: 10..<26)
        } else {
            depthGained = 0
            torchChange = Int.random(in: 10..<21)
        }

        depth += depthGained
        torchLight = min(torchLight + torchChange, 100)

        let name = isBot ? (isPlayer ? "You" : "Bot") : (isPlayer ? "Player 1" : "Player 2")
        if explore {
            turnMessage = "\(name) explored \(depthGained)m deeper and lost \(-torchChange)% torch light!"
        } else {
            turnMessage = "\(name) rested and relit \(torchChange)% torch light."
        }

        if torchLight <= 0 {
            let winner = isBot ? (isPlayer ? "Bot" : "You") : (isPlayer ? "Player 2" : "Player 1")
            roundOver = CaveRoundOverInfo(message: "\(name) ran out of light at \(depth)m! \(name) LOSES! \(winner) WINS! 🏆")
            torchLight = 100
            depth = 0
            // Whoever just ran out of light doesn't automatically go first
            // again - toggling (not forcing true) hands the opening move to
            // whoever didn't just lose, matching the nearby-multiplayer
            // branch's fairness rule. In vs-bot mode this can toggle onto
            // the bot's turn, so it needs the exact same scheduleBotMove()
            // kick the non-loss branch already has below - without it the
            // bot would never move and the game would hang.
            isPlayerTurn.toggle()
            if !isPlayerTurn && isBot {
                scheduleBotMove()
            }
        } else {
            isPlayerTurn.toggle()

            if !isPlayerTurn && isBot {
                scheduleBotMove()
            }
        }
    }

    // DIFFICULTY only ever changes the BOT's own choices, not the human
    // player's - there's no way to make the player's own taps "smarter", so
    // the fair thing is to give the bot better (HARD) or worse (EASY) torch
    // management instead: a HARD bot rests earlier/more often to stay safe,
    // an EASY bot pushes its luck and rarely stops to rest. MEDIUM sits in
    // between.
    private func scheduleBotMove() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.isStopped else { return }
            let restThreshold: Int
            switch self.difficulty {
            case "HARD": restThreshold = 55
            case "EASY": restThreshold = 15
            default: restThreshold = 35 // MEDIUM
            }
            let explore = self.torchLight > restThreshold
            self.takeTurn(isPlayer: false, explore: explore)
        }
    }

    func stop() {
        isStopped = true
        if isNearby { InternetConnectionManager.shared.stop() }
    }
}

struct CaveRoundOverInfo: Identifiable {
    let id = UUID()
    let message: String
}
