import SwiftUI

/// Mirrors HangmanActivity.kt. Guess the secret word one letter at a time
/// before you run out of lives - solo/vs-bot (random word), local
/// pass-and-play (word-entry + phone-handoff, no network), or real internet
/// multiplayer with any number of players. Nearby games pick a WORD_MODE up
/// front on HangmanModeChoiceView:
/// - PICKER: one seat (rotating every round) types in a secret word; every
///   other seat is a simultaneous guesser sharing one pooled board (shared
///   guessed-letters/lives), same as everyone crowding around one Hangman
///   sheet - any of them can call out a letter, and the whole "team" wins or
///   loses together. The picker's own screen mirrors every guess live as it
///   arrives (see applyGuessAsPicker) but never guesses itself.
/// - RACE: every phone gets the exact same random word/category (seat 0
///   always rolls it - since nobody actually competes to be the roller, who
///   rolls doesn't matter for fairness) and everyone guesses independently;
///   first to finish wins.
///
/// Since the full player list (in a fixed, agreed-upon order) now arrives up
/// front via GameSelection.players, there's no need for the old per-round
/// HELLO token handshake at all - "whose turn is it to pick" is just a
/// rotating index into that same list, exactly like Memory Match and Count21.
struct HangmanView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    private let isNearbyGame: Bool
    private let isBotGame: Bool
    private let difficulty: String
    private let isRaceMode: Bool
    private let players: [Player]
    private let myId: String?

    init(selection: GameSelection) {
        self.isNearbyGame = selection.isNearby
        self.isBotGame = selection.isBot
        self.difficulty = selection.difficulty ?? "EASY"
        self.isRaceMode = selection.isNearby && selection.wordMode == "RACE"
        self.players = selection.players ?? []
        self.myId = InternetConnectionManager.shared.myPlayerId()
    }

    private static let wordMap: [String: [String]] = [
        "Animals": ["TIGER", "ELEPHANT", "GIRAFFE", "MONKEY", "RABBIT"],
        "Countries": ["BRAZIL", "FRANCE", "CANADA", "JAPAN", "EGYPT"],
        "Fruits": ["BANANA", "ORANGE", "CHERRY", "GRAPES", "MANGO"],
        "BuddyVerse": ["BUDDY", "GAMES", "MOBILE", "PLANET", "LOBBY"]
    ]

    // Which "screen" is currently up - mirrors the visibility toggling
    // HangmanActivity does across wordEntrySection / hangmanView /
    // tvWordDisplay / keyboardGrid.
    private enum Phase {
        case connecting
        case wordEntry        // typing a word, or (local mode) the phone-handoff step
        case waitingForWord   // guesser/racer: waiting for the word to arrive
        case spectating        // picker mode: watching the group's progress live
        case playing            // actually guessing
    }

    @State private var phase: Phase = .connecting

    @State private var targetWord = ""
    @State private var lives = 6
    @State private var guessedLetters: Set<Character> = []
    @State private var wrongLetters: Set<Character> = []

    @State private var isSpectator = false
    // Local pass-and-play only: true once Player 1 has typed and submitted
    // their word and the word-entry section has swapped into the "pass the
    // phone" handoff step.
    @State private var awaitingLocalHandoff = false
    @State private var pickerIndex = 0
    @State private var roundOver = false
    @State private var roundId = 0

    @State private var categoryText = "Category: Animals"
    @State private var wordEntryPrompt = "Pick a secret word for your friend to guess!"
    @State private var submitButtonLabel = "Submit Word"
    @State private var wordEntryInput = ""

    @State private var didSetup = false
    @State private var didHandleDisconnect = false
    @State private var toastMessage: String?
    @State private var toastToken = UUID()
    @State private var runToken = UUID()
    @State private var showFeedback = false
    @State private var showReport = false

    private var displayWord: String {
        targetWord.map { guessedLetters.contains($0) ? String($0) : "_" }.joined(separator: " ")
    }

    private var showKeyboard: Bool { phase == .playing || phase == .spectating }
    private var keyboardEnabled: Bool { phase == .playing && !roundOver }

    private func isPicker() -> Bool {
        guard !players.isEmpty else { return false }
        return players[pickerIndex % players.count].id == myId
    }

    var body: some View {
        ZStack {
            Color(hex: 0x607D8B).ignoresSafeArea()

            VStack(spacing: 8) {
                Text("Hangman")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text(categoryText)
                    .italic()
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: 0xFFEB3B))
                    .multilineTextAlignment(.center)

                if phase == .wordEntry {
                    wordEntrySection
                }

                if phase == .waitingForWord || phase == .playing || phase == .spectating {
                    HangmanFigureView(livesLeft: lives)
                        .frame(width: 150, height: 150)
                        .padding(.bottom, 4)

                    if phase == .playing || phase == .spectating {
                        Text(displayWord)
                            .font(.system(size: 26))
                            .tracking(2)
                            .foregroundColor(.white)
                    }
                }

                if showKeyboard {
                    ScrollView {
                        keyboardGrid
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    // btnNewHangman: weight 1, bg white, text #607D8B
                    Button("New") { onNewPressed() }
                        .buttonStyle(LegacyProminentButtonStyle(tint: .white))
                        .foregroundColor(Color(hex: 0x607D8B))
                        .frame(maxWidth: .infinity)

                    // btnBackHangman: weight 1, bg #AADDDDDD, text #333333
                    HStack(spacing: 10) {
                        Button("Back") { router.pop() }
                        Button("Home") { router.popToRoot() }
                    }
                    .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0)))
                    .foregroundColor(Color(hex: 0x333333))
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 10) {
                    Button("Feedback") { showFeedback = true }
                    Button("Report") { showReport = true }
                }
                .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0)))
                .foregroundColor(Color(hex: 0x333333))
            }
            .padding(12)

            toastOverlay
        }
        .confettiOverlay(confetti)
        .navigationBarBackButtonHidden(true)
        .onAppear { setupIfNeeded() }
        .onDisappear {
            if isNearbyGame { InternetConnectionManager.shared.stop() }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "HANGMAN") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "HANGMAN") }
    }

    private var wordEntrySection: some View {
        VStack(spacing: 12) {
            Text(wordEntryPrompt)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if !awaitingLocalHandoff {
                TextField("Type a word...", text: $wordEntryInput)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
            }

            Button(submitButtonLabel) { onWordEntryButtonClicked() }
                .buttonStyle(LegacyProminentButtonStyle(tint: .white))
                .foregroundColor(Color(hex: 0x607D8B))
        }
        .padding(.bottom, 12)
    }

    private var keyboardGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), id: \.self) { c in
                let used = guessedLetters.contains(c) || wrongLetters.contains(c)
                Button(String(c)) { onLetterGuessed(c) }
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .font(.system(size: 12, weight: .semibold))
                    .background(keyColor(c))
                    .foregroundColor(.black)
                    .disabled(!keyboardEnabled || used || isSpectator)
            }
        }
    }

    private func keyColor(_ c: Character) -> Color {
        if guessedLetters.contains(c) { return Color(hex: 0x4CAF50) }
        if wrongLetters.contains(c) { return Color(hex: 0xF44336) }
        return Color.white.opacity(0.85)
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
            pickerIndex = 0
            InternetConnectionManager.shared.setListeners(
                onMessage: { msg in DispatchQueue.main.async { receiveNearbyMessage(msg) } },
                onDisconnected: { DispatchQueue.main.async { handleOpponentDisconnected() } }
            )
            // The full player list already arrived up front, so there's no
            // handshake to wait on - jump straight into the first round.
            restartNearbyRound()
        } else if isBotGame {
            startNewGame()
        } else {
            // Local pass-and-play: reuse the same word-entry screen the
            // online "Two Phones" mode uses, so Player 1 can type a custom
            // word instead of always getting a random one.
            beginLocalPassAndPlayRound()
        }
    }

    private func startNewGame() {
        let category = Self.wordMap.keys.randomElement()!
        let pool = Self.wordMap[category]!
        let candidates = pool.filter { wordFitsDifficulty($0) }
        let finalPool = candidates.isEmpty ? pool : candidates
        let word = finalPool.randomElement()!
        startRoundWithWord(category, word)
    }

    private func wordFitsDifficulty(_ word: String) -> Bool {
        switch difficulty {
        case "EASY": return word.count <= 5
        case "HARD": return word.count >= 6
        default: return true // MEDIUM (and default) - no length restriction
        }
    }

    private func startRoundWithWord(_ category: String, _ word: String) {
        targetWord = word
        guessedLetters = []
        wrongLetters = []
        lives = 6
        roundOver = false
        isSpectator = isNearbyGame && !isRaceMode && isPicker()

        phase = .playing
        categoryText = isRaceMode
            ? "Category: \(category) - race to guess it!"
            : (isNearbyGame ? "Guess the secret word!" : "Category: \(category)")
    }

    // MARK: - Nearby round flow (PICKER mode)

    // Seat pickerIndex types in the secret word this round; everyone else is
    // a guesser and waits for that word to arrive over the wire.
    private func beginNearbyRound() {
        roundOver = false
        isSpectator = isPicker()
        if isSpectator {
            wordEntryInput = ""
            let guesserNames = players.isEmpty ? [] : players.enumerated().filter { $0.offset != pickerIndex % players.count }.map { $0.element.name }
            let guesserLabel = guesserNames.count <= 1 ? (guesserNames.first ?? "your friend") : "the group"
            wordEntryPrompt = "Pick a secret word for \(guesserLabel) to guess!"
            submitButtonLabel = "Submit Word"
            phase = .wordEntry
            categoryText = "Pick a word for \(guesserLabel) to guess!"
        } else {
            phase = .waitingForWord
            targetWord = ""
            let pickerName = players[safe: pickerIndex % max(players.count, 1)]?.name ?? "someone"
            categoryText = "Waiting for \(pickerName) to pick a word..."
        }
    }

    // Called both on the very first connect and every time anyone taps "New"
    // in nearby mode. Picker mode just replays the same pick-a-word/wait
    // split every round (whoever picks rotates via pickerIndex, already
    // tracked). Race mode has no fixed picker role and no handshake to
    // redo - seat 0 simply rolls a fresh random word every round, since
    // there's no competitive advantage to being the roller.
    private func restartNearbyRound() {
        roundOver = false
        if isRaceMode {
            phase = .connecting
            targetWord = ""
            if let seat0 = players.first, seat0.id == myId {
                categoryText = "Rolling a word..."
                rollRaceWord()
            } else {
                categoryText = "Waiting for a random word..."
            }
        } else {
            beginNearbyRound()
        }
    }

    // Race mode only: seat 0 rolls a random word/category and sends it to
    // everyone else so all boards start racing on the exact same word.
    private func rollRaceWord() {
        let category = Self.wordMap.keys.randomElement()!
        let pool = Self.wordMap[category]!
        let word = pool.randomElement()!
        InternetConnectionManager.shared.sendMessage("\(roundId):RACEWORD:\(category):\(word)")
        startRoundWithWord(category, word)
    }

    // MARK: - Local pass-and-play

    private func beginLocalPassAndPlayRound() {
        awaitingLocalHandoff = false
        wordEntryInput = ""
        wordEntryPrompt = "Player 1: pick a secret word for Player 2 to guess!"
        submitButtonLabel = "Submit Word"
        categoryText = "Player 1 is picking a word..."
        phase = .wordEntry
    }

    // The word-entry section's single button does double duty: for the
    // picker it submits the typed word, then (local pass-and-play only) it
    // flips into the "I'm ready" trigger once the phone has been handed
    // off to the guesser.
    private func onWordEntryButtonClicked() {
        if awaitingLocalHandoff {
            beginLocalGuessing()
        } else {
            submitPickedWord()
        }
    }

    // Called when the picker submits a word. Online, this sends the word to
    // everyone else. Locally, both players share this one phone, so the
    // word can't be revealed on screen the same way - instead this swaps
    // the word-entry section into a "pass the phone" handoff step.
    private func submitPickedWord() {
        let word = wordEntryInput.trimmingCharacters(in: .whitespaces).uppercased().filter { $0.isLetter }
        guard word.count >= 2 else {
            showToast("Type a word with at least 2 letters.")
            return
        }
        targetWord = word

        if isNearbyGame {
            InternetConnectionManager.shared.sendMessage("\(roundId):WORD:\(word)")
            beginSpectating(word)
        } else {
            awaitingLocalHandoff = true
            wordEntryPrompt = "Word set! Pass the phone to Player 2, then tap Ready when they have it."
            submitButtonLabel = "Ready - Start Guessing!"
        }
    }

    // Called when Player 2 (now holding the phone) taps "Ready - Start
    // Guessing!" after the handoff step. Starts the round locally with the
    // word Player 1 just typed - no wire message involved.
    private func beginLocalGuessing() {
        awaitingLocalHandoff = false
        startRoundWithWord("Player 2's Word", targetWord)
        categoryText = "Player 2: guess Player 1's word!"
    }

    // MARK: - Picker mode: spectating the group's progress

    // Picker mode only: the picker's view after submitting the word -
    // mirrors the group's shared board (stickman, blanks, keyboard) so the
    // picker can watch letters light up green/red as GUESS: messages arrive
    // live. Every key stays disabled the whole time - the picker already
    // knows the word and isn't the one guessing it. Win/lose is still
    // decided only by the RESULT:WIN/LOSE message from a guesser, exactly
    // as before this feature existed - this just keeps the screen in sync
    // without the picker trying to independently declare the round over itself.
    private func beginSpectating(_ word: String) {
        isSpectator = true
        roundOver = false
        targetWord = word
        guessedLetters = []
        wrongLetters = []
        lives = 6
        phase = .spectating
        categoryText = "The group is guessing your word..."
    }

    // Mirrors a guess arriving from someone else's phone - used both by the
    // picker (pure spectator, never checks for round-over itself) and by
    // every other guesser (who DOES need to check, since any one of them
    // completing the word or running out of shared lives ends the round for
    // the whole group).
    private func applyGuessAsPicker(_ char: Character) {
        guard !roundOver, !guessedLetters.contains(char), !wrongLetters.contains(char) else { return }
        applyGuessToBoard(char)
    }

    private func applyGuessToBoard(_ char: Character) {
        if targetWord.contains(char) {
            guessedLetters.insert(char)
        } else {
            lives = max(lives - 1, 0)
            wrongLetters.insert(char)
        }
    }

    // MARK: - Guessing

    private func onLetterGuessed(_ char: Character) {
        guard !roundOver, !guessedLetters.contains(char), !wrongLetters.contains(char) else { return }
        applyGuessToBoard(char)
        if isNearbyGame && !isRaceMode && !isSpectator {
            // Broadcasts this guess to everyone else sharing the board
            // (picker mirrors it; every other guesser applies it too so the
            // whole group's board stays in sync).
            InternetConnectionManager.shared.sendMessage("\(roundId):GUESS:\(char)")
        }
        checkGameStatus()
    }

    private func checkGameStatus() {
        if !displayWord.contains("_") {
            roundOver = true
            if isRaceMode {
                showToast("YOU WIN THE RACE! The word was \(targetWord)")
                // Toasts alone are unreliable for something as important as
                // round-over feedback (this app's Android side hit that
                // exact issue), so a persistent on-screen message
                // (categoryText) carries this too.
                categoryText = "\u{1F389} You won the race! The word was \(targetWord)"
                confetti.start()
                InternetConnectionManager.shared.sendMessage("\(roundId):RESULT:RACEWIN:\(myId ?? "")")
            } else if isNearbyGame {
                showToast("YOUR TEAM WINS! The word was \(targetWord)")
                categoryText = "\u{1F389} You win! The word was \(targetWord)"
                confetti.start()
                InternetConnectionManager.shared.sendMessage("\(roundId):RESULT:WIN")
                // The picker's turn moves to the next seat, since this
                // seat's word just got guessed.
                if !players.isEmpty { pickerIndex = (pickerIndex + 1) % players.count }
            } else {
                showToast("YOU WIN! The word was \(targetWord)")
                confetti.start()
            }
        } else if lives <= 0 {
            roundOver = true
            showToast("GAME OVER! The word was \(targetWord)")
            if isNearbyGame {
                categoryText = "\u{1F480} Game over! The word was \(targetWord)"
            }
            if isNearbyGame && !isRaceMode {
                InternetConnectionManager.shared.sendMessage("\(roundId):RESULT:LOSE")
                if !players.isEmpty { pickerIndex = (pickerIndex + 1) % players.count }
            }
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
            restartNearbyRound()
            return
        }

        guard msgRound == roundId else { return }
        handleNearbyMessage(msg)
    }

    private func handleNearbyMessage(_ msg: String) {
        if msg.hasPrefix("RACEWORD:") {
            let rest = msg.dropFirst("RACEWORD:".count)
            guard let catSep = rest.firstIndex(of: ":") else { return }
            let category = String(rest[rest.startIndex..<catSep])
            let word = String(rest[rest.index(after: catSep)...])
            // Mirror submitPickedWord()'s letters-only guard - a modified
            // client sending digits/symbols would otherwise make part of
            // the word permanently unguessable.
            if !word.isEmpty && word.allSatisfy({ $0.isLetter }) {
                startRoundWithWord(category, word)
            }
        } else if msg.hasPrefix("WORD:") {
            let word = String(msg.dropFirst("WORD:".count))
            if !word.isEmpty && word.allSatisfy({ $0.isLetter }) {
                let pickerName = players[safe: pickerIndex % max(players.count, 1)]?.name ?? "Friend"
                startRoundWithWord("\(pickerName)'s Word", word)
            }
        } else if msg.hasPrefix("GUESS:") {
            // Lets everyone sharing the board watch each guess land live -
            // the picker just mirrors it, every other guesser also needs to
            // check whether this particular guess just ended the round for
            // the whole group.
            let rest = msg.dropFirst("GUESS:".count)
            guard rest.count == 1, let char = rest.first else { return }
            if isSpectator {
                applyGuessAsPicker(char)
            } else if !roundOver, !guessedLetters.contains(char), !wrongLetters.contains(char) {
                applyGuessToBoard(char)
                checkGameStatus()
            }
        } else if msg == "RESULT:WIN" {
            // Arrives from whichever guesser's move actually ended the
            // round - everyone else (picker included) uses it to learn the
            // round is over and rotate the picker seat, without needing to
            // detect it independently themselves.
            if !roundOver {
                roundOver = true
                showToast("The group guessed your word! \u{1F389}")
                categoryText = "\u{1F389} The group guessed your word!"
                if isSpectator { confetti.start() }
                if !players.isEmpty { pickerIndex = (pickerIndex + 1) % players.count }
            }
        } else if msg == "RESULT:LOSE" {
            if !roundOver {
                roundOver = true
                showToast("The group ran out of guesses! The word was \(targetWord).")
                categoryText = "\u{1F480} The group ran out of guesses! The word was \(targetWord)."
                if !players.isEmpty { pickerIndex = (pickerIndex + 1) % players.count }
            }
        } else if msg.hasPrefix("RESULT:RACEWIN:") {
            // Race mode only - someone else finished guessing first.
            if !roundOver {
                roundOver = true
                let winnerId = String(msg.dropFirst("RESULT:RACEWIN:".count))
                let winnerName = players.first(where: { $0.id == winnerId })?.name ?? "Someone"
                showToast("\(winnerName) finished first! The word was \(targetWord).")
                categoryText = "\u{1F3C1} \(winnerName) finished first! The word was \(targetWord)."
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

    private func onNewPressed() {
        if isNearbyGame {
            roundId += 1
            InternetConnectionManager.shared.sendMessage("\(roundId):RESET")
            restartNearbyRound()
        } else if isBotGame {
            startNewGame()
        } else {
            beginLocalPassAndPlayRound()
        }
    }

    // MARK: - Small helpers

    private func runAfterDelay(_ seconds: Double, action: @escaping () -> Void) {
        let token = runToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if token == runToken { action() }
        }
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Draws the stickman-and-gallows figure, revealing one more body part for
/// every life lost. Mirrors HangmanView.kt's Canvas onDraw exactly (same
/// proportional coordinates, same lives-left thresholds). Named
/// HangmanFigureView instead of HangmanView to avoid colliding with the
/// top-level screen type above.
struct HangmanFigureView: View {
    let livesLeft: Int

    var body: some View {
        // `Canvas` needs iOS 15 - `Path` itself has conformed to `Shape`
        // (so it can be `.stroke()`d/`.fill()`d directly) since iOS 13,
        // which is all this drawing actually needs.
        GeometryReader { geo in
            buildPath(in: geo.size)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    private func buildPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()

            // Gallows.
            path.move(to: CGPoint(x: w * 0.1, y: h * 0.9))
            path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.9)) // base
            path.move(to: CGPoint(x: w * 0.3, y: h * 0.9))
            path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.1)) // post
            path.move(to: CGPoint(x: w * 0.3, y: h * 0.1))
            path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.1)) // beam
            path.move(to: CGPoint(x: w * 0.7, y: h * 0.1))
            path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.2)) // rope

            // Stickman, revealed based on lives left.
            if livesLeft < 6 {
                let r = w * 0.1
                path.addEllipse(in: CGRect(x: w * 0.7 - r, y: h * 0.3 - r, width: r * 2, height: r * 2)) // head
            }
            if livesLeft < 5 {
                path.move(to: CGPoint(x: w * 0.7, y: h * 0.4))
                path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.65)) // body
            }
            if livesLeft < 4 {
                path.move(to: CGPoint(x: w * 0.7, y: h * 0.45))
                path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.55)) // left arm
            }
            if livesLeft < 3 {
                path.move(to: CGPoint(x: w * 0.7, y: h * 0.45))
                path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.55)) // right arm
            }
            if livesLeft < 2 {
                path.move(to: CGPoint(x: w * 0.7, y: h * 0.65))
                path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.8)) // left leg
            }
            if livesLeft < 1 {
                path.move(to: CGPoint(x: w * 0.7, y: h * 0.65))
                path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.8)) // right leg
            }

            return path
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
