import SwiftUI

/// Mirrors ArcticTrekActivity. Unlike Desert Trek's single "walk forward"
/// button, each turn here is a blind choice between two ice paths - Left or
/// Right. Either path might turn out to be solid ice (small warmth loss,
/// good progress) or thin ice (big warmth loss, barely any progress) -
/// there's no way to tell which in advance, so it plays like a simple
/// gamble rather than a resource-mash. There's one shared warmth/distance
/// pool everyone takes turns contributing to (vs a bot, two people passing
/// one phone, or now any number of people online) - whoever's turn empties
/// the shared warmth pool freezes and loses; everyone else wins.
///
/// Real multiplayer here is built from scratch (unlike Tic-Tac-Toe/Hangman/
/// Memory/Count21, which already had it) - since there's real randomness
/// every turn (which path is thin ice, how much it costs), whoever's turn it
/// is resolves that randomness locally and broadcasts the resolved numbers,
/// and everyone else just applies them - nobody re-rolls their own copy, so
/// every phone ends up with the exact same warmth/distance no matter whose
/// turn it was.
struct ArcticTrekView: View {
    @StateObject private var vm: ArcticTrekViewModel
    @EnvironmentObject private var router: Router
    @State private var showFeedback = false
    @State private var showReport = false

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: ArcticTrekViewModel(
            isBot: selection.isBot,
            difficulty: selection.difficulty ?? "EASY",
            isNearby: selection.isNearby,
            players: selection.players ?? []
        ))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Arctic Trek")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Text(vm.turnLabel)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 8)

            Text("Warmth Level: \(max(vm.warmth, 0))%")
                .font(.system(size: 20))
                .foregroundColor(.white)

            Text("Distance: \(vm.distance)km")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(.bottom, 20)

            Text("🥶")
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
                    vm.choosePath(left: true)
                } label: {
                    Text("⬅️ Left Path")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.white)
                .foregroundColor(Color(hex: 0x0288D1))

                Button {
                    vm.choosePath(left: false)
                } label: {
                    Text("Right Path ➡️")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.white)
                .foregroundColor(Color(hex: 0x0288D1))
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

            HStack(spacing: 10) {
                Button("Feedback") { showFeedback = true }
                Button("Report") { showReport = true }
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: 0xDDDDDD, opacity: 0.67))
            .foregroundColor(Color(hex: 0x333333))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x0288D1).ignoresSafeArea())
        .navigationTitle("Arctic Trek")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $vm.roundOver) { (info: ArcticRoundOverInfo) in
            Alert(title: Text("Round Over"), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
        .onChange(of: vm.isDisconnected) { disconnected in
            if disconnected { router.push(.opponentDisconnected) }
        }
        .onAppear {
            vm.turnMessage = "Pick a path each turn - one might be thin ice!"
            vm.startIfNeeded()
        }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "ARCTIC") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "ARCTIC") }
    }
}

/// Owns all game state/timing so the timer-driven bot move survives SwiftUI
/// body re-evaluations the same way the Activity's mutable fields survive
/// across click callbacks - a plain `@State` struct field would get a fresh
/// copy captured in the delayed closure instead of the live value.
@MainActor
final class ArcticTrekViewModel: ObservableObject {
    @Published var warmth = 100
    @Published var distance = 0
    @Published var isPlayerTurn = true
    @Published var turnMessage = ""
    @Published var roundOver: ArcticRoundOverInfo?
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

    // When there's no bot, this is a local pass-and-play screen shared by
    // both players - the button must stay live for whichever player's turn
    // it currently is, alternating every move rather than ever going dead.
    var buttonsEnabled: Bool {
        if isNearby { return !players.isEmpty && isMyTurn() }
        return isBot ? isPlayerTurn : true
    }

    func choosePath(left: Bool) {
        guard buttonsEnabled else { return }

        if isNearby {
            // Human odds are always the flat 40% - the DIFFICULTY-based bias
            // only ever applied to a bot, and there's no bot here.
            let isThinIce = Int.random(in: 0..<100) < 40
            let distGain = isThinIce ? Int.random(in: 0..<3) : Int.random(in: 3..<11)
            let warmthLost = isThinIce ? Int.random(in: 15..<31) : Int.random(in: 2..<9)
            let sentRoundId = roundId
            guard let actorId = myId else { return }
            applyNearbyTurn(actorId: actorId, chosePathLeft: left, isThinIce: isThinIce, distGain: distGain, warmthLost: warmthLost)
            InternetConnectionManager.shared.sendMessage(
                "\(sentRoundId):TURN:\(actorId):\(left ? "L" : "R"):\(isThinIce ? "THIN" : "SOLID"):\(distGain):\(warmthLost)"
            )
            return
        }

        takeTurn(isPlayer: isPlayerTurn, chosePathLeft: left)
    }

    // Applies one resolved turn (from either this device or a message from
    // someone else's) to the shared warmth/distance pool. Every phone in the
    // room calls this with the exact same numbers for the exact same turn,
    // so they all end up in perfect agreement about the shared state.
    private func applyNearbyTurn(actorId: String, chosePathLeft: Bool, isThinIce: Bool, distGain: Int, warmthLost: Int) {
        let actorName = players.first(where: { $0.id == actorId })?.name ?? "Someone"
        distance += distGain
        warmth -= warmthLost

        let pathName = chosePathLeft ? "Left Path" : "Right Path"
        let iceDesc = isThinIce ? "hit THIN ICE! ❄️💥" : "found solid ice"
        turnMessage = "\(actorName) took the \(pathName) and \(iceDesc) (-\(warmthLost)% warmth)"

        if warmth <= 0 {
            let iFroze = actorId == myId
            turnMessage = iFroze
                ? "You froze at \(distance)km! YOU LOSE!"
                : "\(actorName) froze at \(distance)km and loses! Everyone else wins! 🏆"
            warmth = 100
            distance = 0
            // Whoever just froze doesn't automatically go first again -
            // start the next round with the seat right after them.
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
        guard parts.count == 5 else { return }
        let actorId = parts[0]
        guard actorId != myId else { return } // our own move, already applied locally
        let chosePathLeft = parts[1] == "L"
        let isThinIce = parts[2] == "THIN"
        guard let distGain = Int(parts[3]), let warmthLost = Int(parts[4]) else { return }
        applyNearbyTurn(actorId: actorId, chosePathLeft: chosePathLeft, isThinIce: isThinIce, distGain: distGain, warmthLost: warmthLost)
    }

    // DIFFICULTY only ever changes the BOT's own odds, not the human
    // player's - there's no way for either side to "read" which path is
    // safe, so the fair thing is to keep the player's own thin-ice odds
    // fixed and instead give the bot better (HARD) or worse (EASY) luck
    // reading the ice. MEDIUM matches the player's own odds.
    private func takeTurn(isPlayer: Bool, chosePathLeft: Bool) {
        let thinIceChance: Int
        if isBot && !isPlayer {
            switch difficulty {
            case "HARD": thinIceChance = 20
            case "EASY": thinIceChance = 55
            default: thinIceChance = 40 // MEDIUM
            }
        } else {
            thinIceChance = 40
        }
        let isThinIce = Int.random(in: 0..<100) < thinIceChance

        let distGain: Int
        let warmthLost: Int
        if isThinIce {
            distGain = Int.random(in: 0..<3)
            warmthLost = Int.random(in: 15..<31)
        } else {
            distGain = Int.random(in: 3..<11)
            warmthLost = Int.random(in: 2..<9)
        }

        distance += distGain
        warmth -= warmthLost

        let name = isBot ? (isPlayer ? "You" : "Bot") : (isPlayer ? "Player 1" : "Player 2")
        let pathName = chosePathLeft ? "Left Path" : "Right Path"
        let iceDesc = isThinIce ? "hit THIN ICE! ❄️💥" : "found solid ice"
        turnMessage = "\(name) took the \(pathName) and \(iceDesc) (-\(warmthLost)% warmth)"

        if warmth <= 0 {
            let winner = isBot ? (isPlayer ? "Bot" : "You") : (isPlayer ? "Player 2" : "Player 1")
            roundOver = ArcticRoundOverInfo(message: "\(name) froze at \(distance)km! \(name) LOSES! \(winner) WINS! 🏆")
            warmth = 100
            distance = 0
            // Whoever just froze doesn't automatically go first again -
            // toggling (not forcing true) hands the opening move to
            // whoever didn't just freeze, matching the nearby-multiplayer
            // branch's fairness rule above. In vs-bot mode this can toggle
            // onto the bot's turn, so it needs the exact same
            // scheduleBotMove() kick the non-loss branch already has below -
            // without it the bot would never move and the game would hang.
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

    private func scheduleBotMove() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.isStopped else { return }
            // The bot has no more information than the player does - it
            // just picks a side at random.
            self.takeTurn(isPlayer: false, chosePathLeft: Bool.random())
        }
    }

    func stop() {
        isStopped = true
        if isNearby { InternetConnectionManager.shared.stop() }
    }
}

struct ArcticRoundOverInfo: Identifiable {
    let id = UUID()
    let message: String
}
