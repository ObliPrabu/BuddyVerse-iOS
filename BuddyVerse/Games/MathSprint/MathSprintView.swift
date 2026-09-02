import SwiftUI

/// Mirrors MathSprintActivity: a timed arithmetic sprint. Answer as many
/// +/-/* problems as possible before the clock runs out; subtraction always
/// subtracts the smaller number from the larger so answers stay
/// non-negative and age-appropriate. Round length comes straight from
/// MathSprintSelectionView, not from GameSelection.difficulty.
struct MathSprintView: View {
    let roundSeconds: Int
    @EnvironmentObject private var router: Router

    @State private var score = 0
    @State private var timeLeft = 0
    @State private var num1 = 0
    @State private var num2 = 0
    @State private var op = "+"
    @State private var correctAnswer = 0
    @State private var answerText = ""
    @State private var toastMessage: String?
    @State private var timer: Timer?
    @State private var showFeedback = false
    @State private var showReport = false

    private var answerField: some View {
        // `.onSubmit {}` needs iOS 15 - the TextField(_:text:onCommit:)
        // initializer's onCommit gives the same "keyboard return key"
        // behavior back to iOS 13.
        TextField("Answer", text: $answerText, onCommit: { checkAnswer() })
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.center)
            .font(.system(size: 24))
            .frame(width: 200)
            .padding(8)
            .background(Color.white.opacity(0.15))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Time: \(timeLeft)s")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("Score: \(score)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }

            Text("\(num1) \(op) \(num2) = ?")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 50)
                .padding(.bottom, 20)

            if let toastMessage {
                Text(toastMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            // `@FocusState` needs iOS 15 - a stored property of an iOS-15+
            // type can't just be guarded at the use site, so the
            // auto-focusing version lives in its own gated helper. Either
            // way the field is fully usable, just needs a manual tap to
            // bring up the keyboard pre-iOS-15.
            if #available(iOS 15, *) {
                AutoFocusingAnswerField(field: answerField)
            } else {
                answerField
            }

            // btnSubmitAnswer: match_parent, 60dp, bg white, text #FF5722 bold
            Button("SUBMIT") { checkAnswer() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: 0xFF5722))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

            // btnBackMathSprint: match_parent, wrap_content, bg #AADDDDDD, text #333333
            HStack(spacing: 10) {
                Button("Back") { router.pop() }
                Button("Home") { router.popToRoot() }
            }
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0x333333))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button("Feedback") { showFeedback = true }
                Button("Report") { showReport = true }
            }
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0x333333))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xFF5722).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if timeLeft == 0 && timer == nil {
                timeLeft = roundSeconds
                startNewQuestion()
                startTimer()
            }
        }
        .onDisappear { timer?.invalidate() }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "MATH") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "MATH") }
    }

    private func startNewQuestion() {
        var n1 = Int.random(in: 1...20)
        var n2 = Int.random(in: 1...20)
        let chosenOp = ["+", "-", "*"].randomElement() ?? "+"

        // Subtraction always subtracts the smaller from the larger so the
        // answer stays non-negative and age-appropriate.
        if chosenOp == "-" && n2 > n1 {
            swap(&n1, &n2)
        }

        correctAnswer = {
            switch chosenOp {
            case "+": return n1 + n2
            case "-": return n1 - n2
            case "*": return n1 * n2
            default: return n1 + n2
            }
        }()

        num1 = n1
        num2 = n2
        op = chosenOp
        answerText = ""
    }

    private func checkAnswer() {
        guard let userAnswer = Int(answerText), userAnswer == correctAnswer else {
            showToast("Wrong! Try again.")
            return
        }
        score += 1
        startNewQuestion()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeLeft > 0 {
                timeLeft -= 1
            }
            if timeLeft <= 0 {
                timer?.invalidate()
                timer = nil
                showToast("Time's Up! Final Score: \(score)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { router.pop() }
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if toastMessage == message {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

/// Wraps `answerField` with `@FocusState` so it grabs the keyboard the
/// instant a round starts - split out from MathSprintView because a stored
/// property of an iOS-15+-only type can't be conditionally present on a
/// single struct depending on OS version.
@available(iOS 15, *)
private struct AutoFocusingAnswerField<Field: View>: View {
    let field: Field
    @FocusState private var isFocused: Bool

    var body: some View {
        field
            .focused($isFocused)
            .onAppear { isFocused = true }
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
    MathSprintView(roundSeconds: 30)
        .environmentObject(Router())
}
