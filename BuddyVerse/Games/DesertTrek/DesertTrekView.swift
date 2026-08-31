import SwiftUI

/// Mirrors DesertTrekActivity. Unlike Arctic Trek's blind gamble or Cave
/// Explorer's explore-vs-rest trade-off, each turn here is a
/// deterministic-ish stake choice between three buttons: a small Sip, a
/// medium Drink, or a big Gulp of your water supply - bigger stakes mean
/// faster progress but faster depletion, no hidden randomness in which
/// choice is "safe". There's one shared water/distance pool everyone takes
/// turns contributing to (vs a bot, two people passing one phone, or now any
/// number of people online) - whoever's turn empties the shared water pool
/// runs dry and loses; everyone else wins.
///
/// Real multiplayer here is built from scratch (unlike Tic-Tac-Toe/Hangman/
/// Memory/Count21, which already had it) - since there's real randomness
/// every turn (exactly how much water/distance a stake costs), whoever's
/// turn it is resolves that randomness locally and broadcasts the resolved
/// numbers, and everyone else just applies them - nobody re-rolls their own
/// copy, so every phone ends up with the exact same water/distance no
/// matter whose turn it was.
struct DesertTrekView: View {
    @StateObject private var vm: DesertTrekViewModel
    @EnvironmentObject private var router: Router

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: DesertTrekViewModel(
            isBot: selection.isBot,
            difficulty: selection.difficulty ?? "EASY",
            isNearby: selection.isNearby,
            players: selection.players ?? []
        ))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Desert Trek 🏜️")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Text(vm.turnLabel)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 8)

            Text("Water Level: \(max(vm.water, 0))%")
                .font(.system(size: 20))
                .foregroundColor(.white)

            Text("Distance: \(vm.distance)km")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(.bottom, 20)

            Text("🐪")
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

            HStack(spacing: 8) {
                stakeButton(title: "💧 Sip") { vm.takeTurn(stake: 0) }
                stakeButton(title: "🥤 Drink") { vm.takeTurn(stake: 1) }
                stakeButton(title: "🌊 Gulp") { vm.takeTurn(stake: 2) }
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(!vm.buttonsEnabled)
            .opacity(vm.buttonsEnabled ? 1 : 0.5)
            .padding(.bottom, 20)

            Button("Back to Menu") { router.pop() }
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: 0xDDDDDD, opacity: 0.67))
                .foregroundColor(Color(hex: 0x333333))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xFFC107).ignoresSafeArea())
        .navigationTitle("Desert Trek")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $vm.roundOver) { (info: DesertRoundOverInfo) in
            Alert(title: Text("Round Over"), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            vm.turnMessage = "Bigger sips mean faster progress but faster thirst!"
            vm.startIfNeeded()
        }
        .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private func stakeButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white)
        .foregroundColor(Color(hex: 0xFFC107))
    }
}

@MainActor
final class DesertTrekViewModel: ObservableObject {
    @Published var water = 100
    @Published var distance = 0
    @Published var isPlayerTurn = true
    @Published var turnMessage = ""
    @Published var roundOver: DesertRoundOverInfo?

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
            onDisconnected: { }
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

    // Local pass-and-play (no bot) keeps all three buttons live for
    // whichever player's turn it currently is, alternating every move.
    var buttonsEnabled: Bool {
        if isNearby { return !players.isEmpty && isMyTurn() }
        return isBot ? isPlayerTurn : true
    }

    // stake: 0 = Sip (small/safe), 1 = Drink (medium), 2 = Gulp (big/risky)
    func takeTurn(stake: Int) {
        guard buttonsEnabled else { return }

        if isNearby {
            let waterLost: Int
            let travel: Int
            switch stake {
            case 0: waterLost = Int.random(in: 2..<7); travel = Int.random(in: 1..<5)
            case 1: waterLost = Int.random(in: 8..<15); travel = Int.random(in: 5..<10)
            default: waterLost = Int.random(in: 16..<26); travel = Int.random(in: 10..<16)
            }
            let sentRoundId = roundId
            guard let actorId = myId else { return }
            applyNearbyTurn(actorId: actorId, stake: stake, travel: travel, waterLost: waterLost)
            InternetConnectionManager.shared.sendMessage("\(sentRoundId):TURN:\(actorId):\(stake):\(travel):\(waterLost)")
            return
        }

        takeTurn(isPlayer: isPlayerTurn, stake: stake)
    }

    // Applies one resolved turn (from either this device or a message from
    // someone else's) to the shared water/distance pool. Every phone in the
    // room calls this with the exact same numbers for the exact same turn,
    // so they all end up in perfect agreement about the shared state.
    private func applyNearbyTurn(actorId: String, stake: Int, travel: Int, waterLost: Int) {
        let actorName = players.first(where: { $0.id == actorId })?.name ?? "Someone"
        distance += travel
        water -= waterLost

        let stakeName = stake == 0 ? "Sip" : (stake == 1 ? "Drink" : "Gulp")
        turnMessage = "\(actorName) took a \(stakeName) - trekked \(travel) km, used \(waterLost)% water!"

        if water <= 0 {
            let iRanOut = actorId == myId
            turnMessage = iRanOut
                ? "You ran out of water at \(distance)km! YOU LOSE!"
                : "\(actorName) ran out of water at \(distance)km and loses! Everyone else wins! 🏆"
            water = 100
            distance = 0
            let actorIndex = players.firstIndex(where: { $0.id == actorId })
            turnIndex = actorIndex.map { ($0 + 1) % players.count } ?? 0
        } else {
            turnIndex = (turnIndex + 1) % players.count
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
        guard let stake = Int(parts[1]), let travel = Int(parts[2]), let waterLost = Int(parts[3]) else { return }
        applyNearbyTurn(actorId: actorId, stake: stake, travel: travel, waterLost: waterLost)
    }

    private func takeTurn(isPlayer: Bool, stake: Int) {
        let waterLost: Int
        let travel: Int
        switch stake {
        case 0: waterLost = Int.random(in: 2..<7); travel = Int.random(in: 1..<5)
        case 1: waterLost = Int.random(in: 8..<15); travel = Int.random(in: 5..<10)
        default: waterLost = Int.random(in: 16..<26); travel = Int.random(in: 10..<16)
        }

        distance += travel
        water -= waterLost

        let name = isBot ? (isPlayer ? "You" : "Bot") : (isPlayer ? "Player 1" : "Player 2")
        let stakeName = stake == 0 ? "Sip" : (stake == 1 ? "Drink" : "Gulp")
        turnMessage = "\(name) took a \(stakeName) - trekked \(travel) km, used \(waterLost)% water!"

        if water <= 0 {
            let winner = isBot ? (isPlayer ? "Bot" : "You") : (isPlayer ? "Player 2" : "Player 1")
            roundOver = DesertRoundOverInfo(message: "\(name) ran out of water at \(distance)km! \(name) LOSES! \(winner) WINS! 🏆")
            water = 100
            distance = 0
            // Whoever just ran out of water doesn't automatically go first
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
    // the fair thing is to give the bot better (HARD) or worse (EASY) water
    // management instead: a HARD bot rations carefully (mostly Sips, only
    // Gulping when it's still got plenty of water), an EASY bot gulps
    // recklessly most of the time. MEDIUM picks a stake at random.
    private func scheduleBotMove() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.isStopped else { return }
            let stake: Int
            switch self.difficulty {
            case "HARD": stake = self.water > 60 ? Int.random(in: 0..<2) : 0
            case "EASY": stake = Int.random(in: 0..<100) < 70 ? 2 : 1
            default: stake = Int.random(in: 0..<3) // MEDIUM
            }
            self.takeTurn(isPlayer: false, stake: stake)
        }
    }

    func stop() {
        isStopped = true
        if isNearby { InternetConnectionManager.shared.stop() }
    }
}

struct DesertRoundOverInfo: Identifiable {
    let id = UUID()
    let message: String
}
