import SwiftUI

/// Mirrors InstructionsViewActivity/activity_instructions_view.xml: the
/// actual "how to play" text screen - same welcome_gradient background,
/// top-left white/indigo "Back" pill, a translucent-black instructions box,
/// and the green "START GAME" button.
struct InstructionsScreenView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    private var instructions: String {
        switch selection.gameType {
        case "TICTACTOE": return "Get three in a row (horizontal, vertical, or diagonal) to win!"
        case "HANGMAN": return "Guess the secret word before the stickman is fully drawn!"
        case "WORDSEARCH": return "Swipe across the letters to find the hidden word."
        case "MEMORY": return "Flip two cards to find matching emojis."
        case "SUDOKU": return "Fill the 9x9 grid so each row, column, and 3x3 square contains 1-9 once."
        case "MAZE": return "Swipe or use arrows to move the yellow block to the green exit."
        case "COUNT21": return "Don't be the one to reach 21 or you lose!"
        case "RPS": return "Rock beats Scissors, Scissors beats Paper, Paper beats Rock."
        case "SEQUENCE": return "Watch the pattern of colors and repeat them in order."
        case "SLIDE": return "Slide the tiles to arrange numbers 1-8 in order."
        case "SPACE": return "Tap to move your rocket and collect stars."
        case "JUNGLE": return "Tap the jumping fruits as fast as you can."
        case "OCEAN": return "Tap the sea creatures to dive deep before your bubbles run out."
        case "MOUNTAIN": return "Tap STEP at a steady pace - too fast or too slow both cost you!"
        case "DESERT": return "Choose Sip, Drink, or Gulp each turn - bigger stakes, bigger risk."
        case "VOLCANO": return "Tap COOL DOWN when the moving marker is in the green zone to climb!"
        case "ARCTIC": return "Pick a path each turn - Left or Right. One might be thin ice!"
        case "SAVANNA": return "Only tap when you see the target animal - wrong taps cost a strike!"
        case "CAVE": return "Each turn, choose to Explore Deeper or Rest & Relight your torch."
        case "SWAMP": return "Hold WADE and release when the fill is in the green zone."
        case "STORM": return "Watch the storm's path, then tap the quadrants back in the same order."
        case "JOKES": return "Read fun jokes to brighten your day!"
        case "RIDDLES": return "Read a riddle and try to guess the answer!"
        case "TRIVIA": return "Answer multiple choice questions and test your knowledge."
        case "CONVERSATION": return "Answer questions and see what others are saying!"
        default: return "Have fun playing!"
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()

            Button {
                router.pop()
            } label: {
                Text("Back")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0x1A237E))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(16)

            VStack(spacing: 0) {
                Text("How to Play \(selection.gameType)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)

                Text(instructions)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(Color.black.opacity(0x33 / 255.0))
                    .padding(.bottom, 40)

                Button {
                    router.replaceTop(with: .game(selection))
                } label: {
                    Text("START GAME")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color(hex: 0x4CAF50))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarHidden(true)
    }
}
