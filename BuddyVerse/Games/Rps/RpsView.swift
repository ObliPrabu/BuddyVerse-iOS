import SwiftUI

/// Mirrors RpsActivity's bot and local pass-and-play modes. (Android's real
/// two-phone "Nearby" mode for RPS has no actual Firestore wire protocol
/// wired up - IS_NEARBY is effectively dead for this game there - so this
/// port only implements the vs-bot and one-phone-pass-and-play modes.)
///
/// It's advertised on the welcome screen as "Best of 5" - matches are first
/// to 3 round wins (ties don't count toward either side, so a match can run
/// longer than 5 rounds if there are ties along the way). Once a side hits
/// 3, the match is over: picks lock out and a "Play Again" button appears to
/// start a fresh 0-0 match.
struct RpsView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    private var isBotGame: Bool { selection.isBot }
    private var difficulty: String { selection.difficulty ?? "EASY" }

    // "Left" is always this phone's own side - YOU in bot mode, Player 1 in
    // local pass-and-play - and "right" is whoever/whatever is on the other
    // side of the VS. Labels below are just for display.
    private let roundsToWinMatch = 3
    @State private var scoreLeft = 0
    @State private var scoreRight = 0
    @State private var matchOver = false

    @State private var statusText = ""
    @State private var playerText = "YOU: ?"
    @State private var opponentText = "BOT: ?"
    @State private var toastMessage: String?

    // --- Local "one phone, two people" mode ---
    @State private var player1Choice: String?

    private var leftLabel: String { isBotGame ? "YOU" : "PLAYER 1" }
    private var rightLabel: String { isBotGame ? "BOT" : "PLAYER 2" }

    var body: some View {
        // activity_rps.xml: root LinearLayout android:background="#4CAF50"
        VStack(spacing: 0) {
            Text("Rock Paper Scissors")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Text(statusText)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: 0xFFEB3B))
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text("SCORE: \(scoreLeft) - \(scoreRight)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 30)

            if let toastMessage {
                Text(toastMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .transition(.opacity)
                    .padding(.bottom, 10)
            }

            HStack {
                Text(playerText)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text("VS")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFC107))
                Text(opponentText)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 40)

            HStack(spacing: 10) {
                choiceButton("🪨", "Rock")
                choiceButton("📄", "Paper")
                choiceButton("✂️", "Scissors")
            }
            .padding(.bottom, 40)
            .disabled(matchOver)

            if matchOver {
                // btnPlayAgain: match_parent, 60dp, bg #FFC107, text #333333 bold
                Button("Play Again") { resetMatch() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: 0x333333))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color(hex: 0xFFC107))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.bottom, 10)
                    .buttonStyle(.plain)
            }

            // btnBackRps: wrap_content, bg #AADDDDDD, text #333333
            Button("Back to Menu") { router.pop() }
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0x333333))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x4CAF50).ignoresSafeArea())
        .confettiOverlay(confetti)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if statusText.isEmpty { startNewMatchRound() } }
    }

    private func choiceButton(_ emoji: String, _ choice: String) -> some View {
        Button {
            play(choice)
        } label: {
            Text(emoji)
                .font(.system(size: 30))
                .frame(width: 80, height: 80)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Round flow

    // Puts the screen into "ready for a fresh round" state for whichever
    // mode is active. Used both for the very first round of a match and
    // again after "Play Again" resets the score to 0-0.
    private func startNewMatchRound() {
        if isBotGame {
            playerText = "YOU: ?"
            opponentText = "BOT: ?"
            statusText = "Choose your move!"
        } else {
            playerText = "P1: ?"
            opponentText = "P2: ?"
            statusText = "Player 1, choose your move!"
        }
    }

    private func play(_ choice: String) {
        guard !matchOver else { return }

        if isBotGame {
            playerText = "YOU: \(choice)"

            let choices = ["Rock", "Paper", "Scissors"]
            let botChoice: String
            switch difficulty {
            case "HARD": botChoice = Double.random(in: 0..<1) < 0.7 ? counter(to: choice) : (choices.randomElement() ?? "Rock")
            case "MEDIUM": botChoice = Double.random(in: 0..<1) < 0.4 ? counter(to: choice) : (choices.randomElement() ?? "Rock")
            default: botChoice = choices.randomElement() ?? "Rock"
            }

            opponentText = "BOT: \(botChoice)"
            determineWinnerBot(choice, botChoice)
        } else {
            if player1Choice == nil {
                player1Choice = choice
                playerText = "P1 picked!"
                opponentText = "P2: ?"
                statusText = "Pass the phone to Player 2, then choose your move"
            } else {
                let player2Choice = choice
                playerText = "P1: \(player1Choice!)"
                opponentText = "P2: \(player2Choice)"
                determineWinnerLocal(player1Choice!, player2Choice)
                player1Choice = nil
            }
        }
    }

    private func counter(to playerChoice: String) -> String {
        switch playerChoice {
        case "Rock": return "Paper"
        case "Paper": return "Scissors"
        default: return "Rock"
        }
    }

    // Winner logic shared by every mode: true if `a` beats `b`.
    private func beats(_ a: String, _ b: String) -> Bool {
        (a == "Rock" && b == "Scissors") ||
        (a == "Paper" && b == "Rock") ||
        (a == "Scissors" && b == "Paper")
    }

    private func determineWinnerLocal(_ p1: String, _ p2: String) {
        let leftWon: Bool?
        if p1 == p2 {
            statusText = "IT'S A TIE! 🤝"
            leftWon = nil
        } else if beats(p1, p2) {
            statusText = "PLAYER 1 WINS! 🎉"
            confetti.start()
            leftWon = true
        } else {
            statusText = "PLAYER 2 WINS! 🎉"
            confetti.start()
            leftWon = false
        }
        applyRoundResult(leftWon)
    }

    private func determineWinnerBot(_ p: String, _ b: String) {
        let leftWon: Bool?
        if p == b {
            statusText = "IT'S A TIE! 🤝"
            leftWon = nil
        } else if beats(p, b) {
            statusText = "YOU WIN! 🎉"
            showToast("Great job!")
            confetti.start()
            leftWon = true
        } else {
            statusText = "BOT WINS! 🤖"
            leftWon = false
        }
        applyRoundResult(leftWon)
    }

    // Records who won the round that just finished (nil = tie, doesn't move
    // either score) and checks whether that round just clinched the match.
    private func applyRoundResult(_ leftWon: Bool?) {
        guard !matchOver else { return }
        switch leftWon {
        case true: scoreLeft += 1
        case false: scoreRight += 1
        case nil: break
        }
        if scoreLeft >= roundsToWinMatch || scoreRight >= roundsToWinMatch {
            endMatch(matchWinnerIsLeft: scoreLeft > scoreRight)
        }
    }

    // Locks the board once a side reaches 3 round wins and replaces the
    // status line with the final match result.
    private func endMatch(matchWinnerIsLeft: Bool) {
        matchOver = true
        statusText = matchWinnerIsLeft
            ? "\(leftLabel) WON THE MATCH! 🏆 (\(scoreLeft)-\(scoreRight))"
            : "\(rightLabel) WON THE MATCH! 🏆 (\(scoreRight)-\(scoreLeft))"
    }

    // Starts a fresh 0-0 match after one just finished.
    private func resetMatch() {
        scoreLeft = 0
        scoreRight = 0
        matchOver = false
        player1Choice = nil
        startNewMatchRound()
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if toastMessage == message {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#Preview {
    RpsView(selection: GameSelection(gameType: "RPS", difficulty: "EASY", isBot: true))
        .environmentObject(Router())
}
