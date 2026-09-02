import SwiftUI

/// Mirrors TriviaActivity: shows a question with 4 tappable options.
///
/// Turn-based and scored for two people passing the phone: each player
/// answers the same fixed round of 10 questions (one attempt per question,
/// auto-advancing to the next after a brief correct/wrong flash), then a
/// handoff screen passes the phone to player 2, and a final screen compares
/// both scores and declares a winner.
struct TriviaView: View {
    struct Question: Hashable {
        let text: String
        let options: [String]
        let correctAnswer: String
    }

    private enum Phase {
        case playing
        case handoff
        case finished
    }

    private static let roundSize = 10

    let selection: GameSelection
    @EnvironmentObject private var router: Router

    private let pool: [Question]
    @State private var roundQuestions: [Question]
    @State private var questionIndex = 1
    @State private var current: Question
    @State private var selectedOption: String?
    @State private var toastMessage: String?
    @State private var toastToken = 0
    @State private var currentPlayer = 1
    @State private var scores: [Int: Int] = [1: 0, 2: 0]
    @State private var phase: Phase = .playing
    @State private var showFeedback = false
    @State private var showReport = false

    init(selection: GameSelection) {
        self.selection = selection
        let pool = Self.buildPool(from: selection.aiItems)
        self.pool = pool
        let round = Self.drawRound(from: pool)
        _roundQuestions = State(initialValue: round)
        _current = State(initialValue: round.first ?? Question(text: "Question goes here...", options: [], correctAnswer: ""))
    }

    // Draws exactly `roundSize` questions for one round, wrapping/reshuffling
    // if the pool is smaller than that. Both players answer this same set,
    // in the same order, so their scores are directly comparable.
    private static func drawRound(from pool: [Question]) -> [Question] {
        guard !pool.isEmpty else { return [] }
        var result: [Question] = []
        var bag = pool.shuffled()
        while result.count < roundSize {
            if bag.isEmpty { bag = pool.shuffled() }
            result.append(bag.removeLast())
        }
        return result
    }

    // activity_trivia.xml: solid #673AB7 background, no dark-mode override,
    // so this looks identical regardless of the app's theme setting.
    private let screenBg = Color(hex: 0x673AB7)
    private let buttonTextDark = Color(hex: 0x333333)
    private let correctBg = Color(hex: 0x8BC34A)
    private let wrongBg = Color(hex: 0xE57373)
    // #AADDDDDD - a light gray at ~67% alpha, not plain white-with-opacity.
    private let backButtonBg = Color(hex: 0xDDDDDD, opacity: 170.0 / 255.0)

    var body: some View {
        ZStack {
            screenBg.ignoresSafeArea()

            switch phase {
            case .playing: playingView
            case .handoff: handoffView
            case .finished: finishedView
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "TRIVIA") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "TRIVIA") }
    }

    private var playingView: some View {
        ZStack {
            // Root LinearLayout uses android:gravity="center", which centers
            // the whole content block vertically (not just top-aligned).
            VStack(spacing: 0) {
                Text("Trivia")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                Text("Player \(currentPlayer)'s Turn")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 4)

                Text("Question \(questionIndex) of \(Self.roundSize)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 20)

                Text(current.text)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding(.bottom, 40)

                // optionsContainer buttons are built programmatically as
                // plain white buttons with black text (no bold) in
                // TriviaActivity.loadQuestion().
                VStack(spacing: 0) {
                    ForEach(current.options, id: \.self) { option in
                        Button {
                            chooseOption(option)
                        } label: {
                            Text(option)
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(optionBackground(option))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedOption != nil)
                        .padding(.bottom, 10)
                    }
                }
                .padding(.bottom, 20)

                HStack(spacing: 10) {
                    Button {
                        router.pop()
                    } label: {
                        Text("Back")
                            .font(.system(size: 14))
                            .foregroundColor(buttonTextDark)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(backButtonBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        router.popToRoot()
                    } label: {
                        Text("Home")
                            .font(.system(size: 14))
                            .foregroundColor(buttonTextDark)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(backButtonBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        showFeedback = true
                    } label: {
                        Text("Feedback")
                            .font(.system(size: 14))
                            .foregroundColor(buttonTextDark)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(backButtonBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showReport = true
                    } label: {
                        Text("Report")
                            .font(.system(size: 14))
                            .foregroundColor(buttonTextDark)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(backButtonBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 20)

            // Android surfaces "Correct!"/"Wrong!" as a plain system Toast
            // (dark bubble, bottom-center, auto-dismissing) - reproduced here
            // as an overlay rather than inline chrome since a Toast isn't
            // part of the laid-out view hierarchy on Android either.
            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }
            }
        }
    }

    private func optionBackground(_ option: String) -> Color {
        guard let selectedOption else { return .white }
        if option == current.correctAnswer { return correctBg }
        if option == selectedOption { return wrongBg }
        return .white
    }

    private var handoffView: some View {
        VStack(spacing: 0) {
            Text("\u{1F4E3}")
                .font(.system(size: 60))
                .padding(.bottom, 16)
            Text("Player 1 scored \(scores[1] ?? 0) of \(Self.roundSize)!")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Text("Pass the phone to Player 2.")
                .font(.system(size: 18))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)

            Button {
                startPlayerTwoTurn()
            } label: {
                Text("Player 2's Turn - Start")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(screenBg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                Button {
                    router.pop()
                } label: {
                    Text("Back")
                        .font(.system(size: 14))
                        .foregroundColor(buttonTextDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backButtonBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    router.popToRoot()
                } label: {
                    Text("Home")
                        .font(.system(size: 14))
                        .foregroundColor(buttonTextDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backButtonBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    showFeedback = true
                } label: {
                    Text("Feedback")
                        .font(.system(size: 14))
                        .foregroundColor(buttonTextDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backButtonBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    showReport = true
                } label: {
                    Text("Report")
                        .font(.system(size: 14))
                        .foregroundColor(buttonTextDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backButtonBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
    }

    private var finishedView: some View {
        let score1 = scores[1] ?? 0
        let score2 = scores[2] ?? 0
        let winner: String = score1 == score2 ? "It's a tie!" : (score1 > score2 ? "Player 1 wins!" : "Player 2 wins!")
        let topScore = max(score1, score2)
        let congrats = topScore >= 8 ? "Amazing!" : (topScore >= 5 ? "Nice job!" : "Good effort!")

        return VStack(spacing: 0) {
            Text("\u{1F3C6}")
                .font(.system(size: 60))
                .padding(.bottom, 16)
            Text(congrats)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 12)
            Text("Player 1: \(score1) of \(Self.roundSize)")
                .font(.system(size: 20))
                .foregroundColor(.white)
            Text("Player 2: \(score2) of \(Self.roundSize)")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(.bottom, 12)
            Text(winner)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 40)

            Button {
                startNewRound()
            } label: {
                Text("Play Again")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(screenBg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                Button {
                    router.pop()
                } label: {
                    Text("Back")
                        .font(.system(size: 14))
                        .foregroundColor(buttonTextDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backButtonBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    router.popToRoot()
                } label: {
                    Text("Home")
                        .font(.system(size: 14))
                        .foregroundColor(buttonTextDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backButtonBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    showFeedback = true
                } label: {
                    Text("Feedback")
                        .font(.system(size: 14))
                        .foregroundColor(buttonTextDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backButtonBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    showReport = true
                } label: {
                    Text("Report")
                        .font(.system(size: 14))
                        .foregroundColor(buttonTextDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backButtonBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
    }

    private func chooseOption(_ option: String) {
        guard selectedOption == nil else { return }
        selectedOption = option
        if option == current.correctAnswer {
            scores[currentPlayer, default: 0] += 1
            withAnimation { toastMessage = "Correct!" }
        } else {
            withAnimation { toastMessage = "Wrong! It was \(current.correctAnswer)" }
        }

        // Token guards against a fast second tap re-triggering this same
        // scheduled advance before its own timer meant to.
        toastToken += 1
        let myToken = toastToken
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if myToken == toastToken {
                advance()
            }
        }
    }

    private func advance() {
        withAnimation { toastMessage = nil }
        if questionIndex >= Self.roundSize {
            phase = currentPlayer == 1 ? .handoff : .finished
            return
        }
        current = roundQuestions[questionIndex]
        questionIndex += 1
        selectedOption = nil
    }

    private func startPlayerTwoTurn() {
        currentPlayer = 2
        questionIndex = 1
        current = roundQuestions.first ?? Question(text: "Question goes here...", options: [], correctAnswer: "")
        selectedOption = nil
        phase = .playing
    }

    private func startNewRound() {
        let round = Self.drawRound(from: pool)
        roundQuestions = round
        questionIndex = 1
        current = round.first ?? Question(text: "Question goes here...", options: [], correctAnswer: "")
        selectedOption = nil
        currentPlayer = 1
        scores = [1: 0, 2: 0]
        phase = .playing
    }

    // MARK: - Pool building

    private struct AiTrivia: Decodable {
        let question: String?
        let options: [String]?
        let answer: String?
    }

    private static func buildPool(from aiItems: [String]?) -> [Question] {
        let aiQuestions: [Question] = (aiItems ?? []).compactMap { raw in
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(AiTrivia.self, from: data) else { return nil }
            let q = (obj.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let options = (obj.options ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let correct = (obj.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Match case-insensitively/trimmed so minor casing differences from
            // Gemini don't cause an otherwise-valid question to be dropped, but
            // still use the option's own text so later exact-match checks work.
            let matchedOption = options.first { $0.caseInsensitiveCompare(correct) == .orderedSame }
            // Reject options that aren't 4 genuinely distinct strings - a
            // duplicate distractor from Gemini would otherwise render two
            // identical-text buttons.
            guard !q.isEmpty, options.count == 4, Set(options).count == 4, let matchedOption else { return nil }
            return Question(text: q, options: options, correctAnswer: matchedOption)
        }
        if !aiQuestions.isEmpty { return aiQuestions }
        return allQuestions
    }

    // MARK: - Static fallback pool (used whenever AI generation isn't
    // available - ported verbatim from TriviaActivity.kt's allQuestions
    // list, the baseline content most users will actually see).
    private static let allQuestions: [Question] = [
        Question(text: "What is the capital of France?", options: ["London", "Berlin", "Paris", "Rome"], correctAnswer: "Paris"),
        Question(text: "Which planet is known as the Red Planet?", options: ["Earth", "Mars", "Jupiter", "Venus"], correctAnswer: "Mars"),
        Question(text: "What is 5 x 5?", options: ["10", "20", "25", "30"], correctAnswer: "25"),
        Question(text: "Who painted the Mona Lisa?", options: ["Van Gogh", "Picasso", "Da Vinci", "Monet"], correctAnswer: "Da Vinci"),
        Question(text: "Which ocean is the largest?", options: ["Atlantic", "Indian", "Arctic", "Pacific"], correctAnswer: "Pacific"),
        Question(text: "What is the fastest land animal?", options: ["Cheetah", "Lion", "Tiger", "Horse"], correctAnswer: "Cheetah"),
        Question(text: "How many continents are there?", options: ["5", "6", "7", "8"], correctAnswer: "7"),
        Question(text: "What is the hardest natural substance?", options: ["Gold", "Iron", "Diamond", "Stone"], correctAnswer: "Diamond"),
        Question(text: "What do bees collect from flowers?", options: ["Water", "Nectar", "Leaves", "Seeds"], correctAnswer: "Nectar"),
        Question(text: "What is the freezing point of water?", options: ["0\u{00B0}C", "32\u{00B0}C", "10\u{00B0}C", "-5\u{00B0}C"], correctAnswer: "0\u{00B0}C"),
        Question(text: "What is the square root of 64?", options: ["6", "7", "8", "9"], correctAnswer: "8"),
        Question(text: "Who wrote 'Romeo and Juliet'?", options: ["Dickens", "Shakespeare", "Twain", "Austen"], correctAnswer: "Shakespeare"),
        Question(text: "What is the chemical symbol for gold?", options: ["Go", "Gd", "Au", "Ag"], correctAnswer: "Au"),
        Question(text: "Which planet is closest to the Sun?", options: ["Venus", "Mars", "Mercury", "Earth"], correctAnswer: "Mercury"),
        Question(text: "How many colors are in a rainbow?", options: ["5", "6", "7", "8"], correctAnswer: "7"),
        Question(text: "What is the largest organ in the human body?", options: ["Heart", "Liver", "Skin", "Lungs"], correctAnswer: "Skin"),
        Question(text: "Which gas do plants absorb from the atmosphere?", options: ["Oxygen", "Nitrogen", "Carbon Dioxide", "Hydrogen"], correctAnswer: "Carbon Dioxide"),
        Question(text: "What is the capital of Japan?", options: ["Beijing", "Seoul", "Tokyo", "Bangkok"], correctAnswer: "Tokyo"),
        Question(text: "How many teeth does an adult human have?", options: ["28", "30", "32", "34"], correctAnswer: "32"),
        Question(text: "What is the study of stars called?", options: ["Biology", "Astronomy", "Geology", "Chemistry"], correctAnswer: "Astronomy"),
        Question(text: "What is the tallest mountain in the world?", options: ["K2", "Kilimanjaro", "Everest", "Fuji"], correctAnswer: "Everest"),
        Question(text: "Who was the first man to walk on the moon?", options: ["Buzz Aldrin", "Neil Armstrong", "Yuri Gagarin", "John Glenn"], correctAnswer: "Neil Armstrong"),
        Question(text: "What is the capital of Italy?", options: ["Milan", "Naples", "Venice", "Rome"], correctAnswer: "Rome"),
        Question(text: "Which animal is known as the King of the Jungle?", options: ["Tiger", "Elephant", "Lion", "Bear"], correctAnswer: "Lion"),
        Question(text: "What is the chemical symbol for water?", options: ["Wa", "H2O", "O2", "H2"], correctAnswer: "H2O"),
        Question(text: "How many days are in a leap year?", options: ["364", "365", "366", "367"], correctAnswer: "366"),
        Question(text: "What is the primary language spoken in Brazil?", options: ["Spanish", "English", "Portuguese", "French"], correctAnswer: "Portuguese"),
        Question(text: "Which planet is famous for its rings?", options: ["Jupiter", "Mars", "Saturn", "Neptune"], correctAnswer: "Saturn"),
        Question(text: "What is the smallest prime number?", options: ["0", "1", "2", "3"], correctAnswer: "2"),
        Question(text: "Who invented the light bulb?", options: ["Tesla", "Einstein", "Edison", "Newton"], correctAnswer: "Edison"),
        Question(text: "What is the capital of Canada?", options: ["Toronto", "Vancouver", "Montreal", "Ottawa"], correctAnswer: "Ottawa"),
        Question(text: "Which ocean surrounds Hawaii?", options: ["Atlantic", "Indian", "Arctic", "Pacific"], correctAnswer: "Pacific"),
        Question(text: "What is the largest mammal in the world?", options: ["Elephant", "Blue Whale", "Giraffe", "Shark"], correctAnswer: "Blue Whale"),
        Question(text: "How many legs does a spider have?", options: ["6", "7", "8", "10"], correctAnswer: "8"),
        Question(text: "What is the capital of Spain?", options: ["Barcelona", "Seville", "Valencia", "Madrid"], correctAnswer: "Madrid"),
        Question(text: "Who is the author of 'Harry Potter'?", options: ["Roald Dahl", "J.K. Rowling", "Stephen King", "Dr. Seuss"], correctAnswer: "J.K. Rowling"),
        Question(text: "What is the currency of the United Kingdom?", options: ["Dollar", "Euro", "Pound", "Yen"], correctAnswer: "Pound"),
        Question(text: "Which is the smallest continent?", options: ["Africa", "Europe", "Australia", "Antarctica"], correctAnswer: "Australia"),
        Question(text: "What is the capital of Australia?", options: ["Sydney", "Melbourne", "Brisbane", "Canberra"], correctAnswer: "Canberra"),
        Question(text: "How many bones are in the adult human body?", options: ["204", "206", "208", "210"], correctAnswer: "206"),
        Question(text: "What is the process by which plants make food?", options: ["Respiration", "Digestion", "Photosynthesis", "Absorption"], correctAnswer: "Photosynthesis"),
        Question(text: "What is the capital of Egypt?", options: ["Alexandria", "Luxor", "Giza", "Cairo"], correctAnswer: "Cairo"),
        Question(text: "Which bird is often associated with wisdom?", options: ["Eagle", "Parrot", "Owl", "Hawk"], correctAnswer: "Owl"),
        Question(text: "What is the largest country by area?", options: ["USA", "China", "Canada", "Russia"], correctAnswer: "Russia"),
        Question(text: "Which planet is known as the 'Morning Star'?", options: ["Mars", "Venus", "Jupiter", "Saturn"], correctAnswer: "Venus"),
        Question(text: "What is the capital of Germany?", options: ["Munich", "Frankfurt", "Hamburg", "Berlin"], correctAnswer: "Berlin"),
        Question(text: "How many sides does a hexagon have?", options: ["5", "6", "7", "8"], correctAnswer: "6"),
        Question(text: "What is the main ingredient in hummus?", options: ["Beans", "Chickpeas", "Lentils", "Peas"], correctAnswer: "Chickpeas"),
        Question(text: "Which country is home to the Kangaroo?", options: ["India", "Africa", "Australia", "Brazil"], correctAnswer: "Australia"),
        Question(text: "What is the capital of Russia?", options: ["St. Petersburg", "Kazan", "Sochi", "Moscow"], correctAnswer: "Moscow"),
        Question(text: "Who painted the ceiling of the Sistine Chapel?", options: ["Leonardo", "Raphael", "Donatello", "Michelangelo"], correctAnswer: "Michelangelo"),
        Question(text: "What is the boiling point of water in Celsius?", options: ["50\u{00B0}C", "75\u{00B0}C", "100\u{00B0}C", "125\u{00B0}C"], correctAnswer: "100\u{00B0}C"),
        Question(text: "Which metal is liquid at room temperature?", options: ["Iron", "Silver", "Mercury", "Copper"], correctAnswer: "Mercury"),
        Question(text: "What is the capital of Mexico?", options: ["Guadalajara", "Monterrey", "Cancun", "Mexico City"], correctAnswer: "Mexico City"),
        Question(text: "How many minutes are in an hour?", options: ["50", "60", "70", "80"], correctAnswer: "60"),
        Question(text: "Which gas do humans breathe out?", options: ["Oxygen", "Hydrogen", "Nitrogen", "Carbon Dioxide"], correctAnswer: "Carbon Dioxide"),
        Question(text: "What is the capital of China?", options: ["Shanghai", "Guangzhou", "Beijing", "Hong Kong"], correctAnswer: "Beijing"),
        Question(text: "Which is the longest river in the world?", options: ["Amazon", "Nile", "Mississippi", "Yangtze"], correctAnswer: "Nile"),
        Question(text: "Who was the first President of the United States?", options: ["Jefferson", "Adams", "Lincoln", "Washington"], correctAnswer: "Washington"),
        Question(text: "What is the capital of India?", options: ["Mumbai", "Kolkata", "Chennai", "New Delhi"], correctAnswer: "New Delhi"),
        Question(text: "How many wheels does a tricycle have?", options: ["2", "3", "4", "5"], correctAnswer: "3"),
        Question(text: "What is the name of the fairy in 'Peter Pan'?", options: ["Cinderella", "Belle", "Tinker Bell", "Ariel"], correctAnswer: "Tinker Bell"),
        Question(text: "What is the capital of Brazil?", options: ["Rio", "Sao Paulo", "Brasilia", "Salvador"], correctAnswer: "Brasilia"),
        Question(text: "Which fruit is famously associated with Isaac Newton?", options: ["Orange", "Pear", "Banana", "Apple"], correctAnswer: "Apple"),
        Question(text: "What is the capital of Greece?", options: ["Sparta", "Thessaloniki", "Athens", "Patras"], correctAnswer: "Athens"),
        Question(text: "How many players are on a soccer team (on the field)?", options: ["9", "10", "11", "12"], correctAnswer: "11"),
        Question(text: "What is the capital of Portugal?", options: ["Porto", "Coimbra", "Faro", "Lisbon"], correctAnswer: "Lisbon"),
        Question(text: "Which is the fastest bird in the world?", options: ["Eagle", "Peregrine Falcon", "Hawk", "Swift"], correctAnswer: "Peregrine Falcon"),
        Question(text: "What is the capital of Sweden?", options: ["Oslo", "Helsinki", "Copenhagen", "Stockholm"], correctAnswer: "Stockholm"),
        Question(text: "Who wrote 'The Odyssey'?", options: ["Homer", "Virgil", "Socrates", "Plato"], correctAnswer: "Homer"),
        Question(text: "What is the capital of Norway?", options: ["Stockholm", "Bergen", "Oslo", "Stavanger"], correctAnswer: "Oslo"),
        Question(text: "How many stripes are on the American flag?", options: ["11", "12", "13", "14"], correctAnswer: "13"),
        Question(text: "What is the capital of Thailand?", options: ["Phuket", "Pattaya", "Chiang Mai", "Bangkok"], correctAnswer: "Bangkok"),
        Question(text: "Which continent is the Sahara Desert located on?", options: ["Asia", "Africa", "South America", "Australia"], correctAnswer: "Africa"),
        Question(text: "What is the capital of South Korea?", options: ["Busan", "Incheon", "Daegu", "Seoul"], correctAnswer: "Seoul"),
        Question(text: "Who is known as the 'Father of Computers'?", options: ["Bill Gates", "Steve Jobs", "Charles Babbage", "Alan Turing"], correctAnswer: "Charles Babbage"),
        Question(text: "What is the capital of Argentina?", options: ["Cordoba", "Rosario", "Mendoza", "Buenos Aires"], correctAnswer: "Buenos Aires"),
        Question(text: "How many Earths could fit inside the Sun?", options: ["100", "1,000", "10,000", "1.3 million"], correctAnswer: "1.3 million"),
        Question(text: "What is the capital of Turkey?", options: ["Istanbul", "Izmir", "Antalya", "Ankara"], correctAnswer: "Ankara"),
        Question(text: "Which is the most spoken language in the world?", options: ["English", "Spanish", "Hindi", "Mandarin"], correctAnswer: "Mandarin"),
        Question(text: "What is the capital of Switzerland?", options: ["Zurich", "Geneva", "Bern", "Basel"], correctAnswer: "Bern"),
        Question(text: "How many bones does a shark have?", options: ["0", "10", "20", "50"], correctAnswer: "0"),
        Question(text: "What is the capital of Ireland?", options: ["Belfast", "Cork", "Galway", "Dublin"], correctAnswer: "Dublin"),
        Question(text: "Which element is the most abundant in the atmosphere?", options: ["Oxygen", "Hydrogen", "Carbon", "Nitrogen"], correctAnswer: "Nitrogen"),
        Question(text: "What is the capital of New Zealand?", options: ["Auckland", "Christchurch", "Hamilton", "Wellington"], correctAnswer: "Wellington"),
        Question(text: "Who painted 'The Starry Night'?", options: ["Picasso", "Van Gogh", "Rembrandt", "Monet"], correctAnswer: "Van Gogh"),
        Question(text: "What is the capital of Austria?", options: ["Salzburg", "Graz", "Innsbruck", "Vienna"], correctAnswer: "Vienna"),
        Question(text: "How many continents are there in the world?", options: ["5", "6", "7", "8"], correctAnswer: "7"),
        Question(text: "What is the capital of Peru?", options: ["Cusco", "Arequipa", "Lima", "Callao"], correctAnswer: "Lima"),
        Question(text: "Which country is famous for the Eiffel Tower?", options: ["Germany", "Italy", "UK", "France"], correctAnswer: "France"),
        Question(text: "What is the capital of Saudi Arabia?", options: ["Jeddah", "Mecca", "Riyadh", "Dammam"], correctAnswer: "Riyadh"),
        Question(text: "How many days are in a week?", options: ["5", "6", "7", "8"], correctAnswer: "7"),
        Question(text: "What is the capital of South Africa?", options: ["Johannesburg", "Durban", "Cape Town", "Pretoria"], correctAnswer: "Pretoria"),
        Question(text: "Which is the largest planet in our solar system?", options: ["Saturn", "Neptune", "Jupiter", "Uranus"], correctAnswer: "Jupiter"),
        Question(text: "What is the capital of the Netherlands?", options: ["Rotterdam", "Utrecht", "Hague", "Amsterdam"], correctAnswer: "Amsterdam")
    ]
}
