import SwiftUI

/// Mirrors RiddlesActivity: shows a riddle, hides the answer until "Show
/// Answer" is tapped, and "Next Riddle" draws the next one from a shuffled
/// bag (so riddles don't repeat until the whole pool has been shown once,
/// then it reshuffles and keeps going).
///
/// Turn-based for two people passing the phone, in a fixed 10-riddle round:
/// player 1 takes riddles 1-5, player 2 takes riddles 6-10, then a
/// completion screen wraps things up and offers a fresh round.
struct RiddlesView: View {
    struct Riddle: Hashable {
        let question: String
        let answer: String
    }

    private static let roundSize = 10
    private static let batchSize = 5

    private enum Phase {
        case playing
        case handoff
        case complete
    }

    let selection: GameSelection
    @EnvironmentObject private var router: Router

    private let pool: [Riddle]
    @State private var roundRiddles: [Riddle]
    @State private var roundIndex = 1
    @State private var current: Riddle
    @State private var showAnswer = false
    @State private var currentPlayer = 1
    @State private var phase: Phase = .playing
    @State private var showFeedback = false
    @State private var showReport = false

    init(selection: GameSelection) {
        self.selection = selection
        let pool = Self.buildPool(from: selection.aiItems)
        self.pool = pool
        let round = Self.drawRound(from: pool)
        _roundRiddles = State(initialValue: round)
        _current = State(initialValue: round.first ?? Riddle(question: "Tap for a riddle!", answer: ""))
    }

    // Draws exactly `roundSize` riddles for one round, wrapping/reshuffling
    // if the pool is smaller than that.
    private static func drawRound(from pool: [Riddle]) -> [Riddle] {
        guard !pool.isEmpty else { return [] }
        var result: [Riddle] = []
        var bag = pool.shuffled()
        while result.count < roundSize {
            if bag.isEmpty { bag = pool.shuffled() }
            result.append(bag.removeLast())
        }
        return result
    }

    // activity_riddles.xml: solid #03A9F4 background, no dark-mode override,
    // so this looks identical regardless of the app's theme setting.
    private let screenBg = Color(hex: 0x03A9F4)
    private let answerColor = Color(hex: 0xFFEB3B)
    private let buttonTextDark = Color(hex: 0x333333)
    // #AADDDDDD - a light gray at ~67% alpha, not plain white-with-opacity.
    private let backButtonBg = Color(hex: 0xDDDDDD, opacity: 170.0 / 255.0)

    var body: some View {
        ZStack {
            screenBg.ignoresSafeArea()

            switch phase {
            case .playing: roundView
            case .handoff: handoffView
            case .complete: completionView
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "RIDDLES") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "RIDDLES") }
    }

    private var handoffView: some View {
        VStack(spacing: 0) {
            Text("\u{1F4E3}")
                .font(.system(size: 60))
                .padding(.bottom, 16)
            Text("Pass the phone to Player \(currentPlayer)!")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Text("Get ready for the next batch of riddles.")
                .font(.system(size: 18))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)

            Button {
                phase = .playing
            } label: {
                Text("Player \(currentPlayer)'s Turn - Start")
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

    private var completionView: some View {
        VStack(spacing: 0) {
            Text("\u{1F389}")
                .font(.system(size: 60))
                .padding(.bottom, 16)
            Text("All \(Self.roundSize) Riddles Done!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Text("Great job working through them together.")
                .font(.system(size: 18))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
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

    private var roundView: some View {
            // Root LinearLayout uses android:gravity="center", which centers
            // the whole content block vertically (not just top-aligned).
            VStack(spacing: 0) {
                Text("Riddles")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                Text("Player \(currentPlayer)'s Turn")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(answerColor)
                    .padding(.bottom, 4)

                Text("Riddle \(roundIndex) of \(Self.roundSize)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 20)

                Text(current.question)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding(.bottom, 20)

                // Android keeps btnShowAnswer visible even after it's tapped
                // (only tvRiddleAnswer's own visibility toggles) - unlike
                // Jokes, this button never gets removed from the layout.
                Text(current.answer)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(answerColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .opacity(showAnswer ? 1 : 0)
                    .padding(.bottom, 40)

                Button {
                    showAnswer = true
                } label: {
                    Text("Show Answer")
                        .font(.system(size: 18))
                        .foregroundColor(screenBg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)

                Button {
                    showNextRiddle()
                } label: {
                    Text("Next Riddle")
                        .font(.system(size: 18))
                        .foregroundColor(screenBg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
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
    }

    private func showNextRiddle() {
        if roundIndex >= Self.roundSize {
            phase = .complete
            return
        }
        current = roundRiddles[roundIndex]
        roundIndex += 1
        showAnswer = false
        if (roundIndex - 1) % Self.batchSize == 0 {
            currentPlayer = currentPlayer == 1 ? 2 : 1
            phase = .handoff
        }
    }

    private func startNewRound() {
        let round = Self.drawRound(from: pool)
        roundRiddles = round
        roundIndex = 1
        current = round.first ?? Riddle(question: "Tap for a riddle!", answer: "")
        showAnswer = false
        currentPlayer = 1
        phase = .playing
    }

    // MARK: - Pool building

    private struct AiRiddle: Decodable {
        let question: String?
        let answer: String?
    }

    private static func buildPool(from aiItems: [String]?) -> [Riddle] {
        let aiRiddles: [Riddle] = (aiItems ?? []).compactMap { raw in
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(AiRiddle.self, from: data) else { return nil }
            let q = (obj.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let a = (obj.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty, !a.isEmpty else { return nil }
            return Riddle(question: q, answer: a)
        }
        if !aiRiddles.isEmpty { return aiRiddles }
        return allRiddles
    }

    // MARK: - Static fallback pool (used whenever AI generation isn't
    // available - ported verbatim from RiddlesActivity.kt's allRiddles list,
    // the baseline content most users will actually see).
    private static let allRiddles: [Riddle] = [
        Riddle(question: "What has hands but can't clap?", answer: "A clock"),
        Riddle(question: "What has to be broken before you can use it?", answer: "An egg"),
        Riddle(question: "What has one eye but can't see?", answer: "A needle"),
        Riddle(question: "What has legs but doesn't walk?", answer: "A table"),
        Riddle(question: "What has a neck but no head?", answer: "A bottle"),
        Riddle(question: "What is full of holes but still holds water?", answer: "A sponge"),
        Riddle(question: "What is always in front of you but can\u{2019}t be seen?", answer: "The future"),
        Riddle(question: "What can you break, even if you never pick it up or touch it?", answer: "A promise"),
        Riddle(question: "What goes up but never comes down?", answer: "Your age"),
        Riddle(question: "What has many keys but can\u{2019}t open a single lock?", answer: "A piano"),
        Riddle(question: "What has a thumb and four fingers, but is not a hand?", answer: "A glove"),
        Riddle(question: "What gets wet while drying?", answer: "A towel"),
        Riddle(question: "What can you keep after giving it to someone?", answer: "Your word"),
        Riddle(question: "What has words, but never speaks?", answer: "A book"),
        Riddle(question: "What runs but has no legs?", answer: "A river"),
        Riddle(question: "What is black when it\u{2019}s clean and white when it\u{2019}s dirty?", answer: "A chalkboard"),
        Riddle(question: "What has cities, but no houses; mountains, but no trees; and water, but no fish?", answer: "A map"),
        Riddle(question: "What belongs to you, but others use it more than you do?", answer: "Your name"),
        Riddle(question: "I\u{2019}m tall when I\u{2019}m young, and I\u{2019}m short when I\u{2019}m old. What am I?", answer: "A candle"),
        Riddle(question: "What can travel around the world while staying in a corner?", answer: "A stamp"),
        Riddle(question: "What has a head and a tail but no body?", answer: "A coin"),
        Riddle(question: "What building has the most stories?", answer: "A library"),
        Riddle(question: "The more of this there is, the less you see. What is it?", answer: "Darkness"),
        Riddle(question: "What has an eye but can't see anything at all?", answer: "A hurricane"),
        Riddle(question: "What has a bottom at the top?", answer: "Your legs"),
        Riddle(question: "What can you catch but not throw?", answer: "A cold"),
        Riddle(question: "What kind of room has no doors or windows?", answer: "A mushroom"),
        Riddle(question: "I have keys, but no locks and space, and no rooms. You can enter, but you can\u{2019}t leave. What am I?", answer: "A keyboard"),
        Riddle(question: "What has a heart that doesn\u{2019}t beat?", answer: "An artichoke"),
        Riddle(question: "I follow you all day long, but when the night comes, I\u{2019}m gone. What am I?", answer: "Your shadow"),
        Riddle(question: "What has a face and two hands but no arms or legs?", answer: "A clock"),
        Riddle(question: "What gets sharper the more you use it?", answer: "Your brain"),
        Riddle(question: "I am always hungry, I must always be fed. The finger I touch, will soon turn red. What am I?", answer: "Fire"),
        Riddle(question: "What has one eye, but cannot see?", answer: "A needle"),
        Riddle(question: "The person who makes it, sells it. The person who buys it, never uses it. The person who uses it, never knows they are using it. What is it?", answer: "A coffin"),
        Riddle(question: "What is easy to get into but hard to get out of?", answer: "Trouble"),
        Riddle(question: "What can fill a room but takes up no space?", answer: "Light"),
        Riddle(question: "If you drop me I\u{2019}m sure to crack, but give me a smile and I\u{2019}ll always smile back. What am I?", answer: "A mirror"),
        Riddle(question: "I\u{2019}m light as a feather, yet the strongest person can\u{2019}t hold me for five minutes. What am I?", answer: "Breath"),
        Riddle(question: "What has a bed but never sleeps, can run but never walks, and has a bank but no money?", answer: "A river"),
        Riddle(question: "What is so fragile that saying its name breaks it?", answer: "Silence"),
        Riddle(question: "What can you hold in your left hand but not in your right?", answer: "Your right elbow"),
        Riddle(question: "What has many teeth, but cannot bite?", answer: "A comb"),
        Riddle(question: "What has four legs, but can\u{2019}t walk?", answer: "A table"),
        Riddle(question: "What starts with T, ends with T, and has T in it?", answer: "A teapot"),
        Riddle(question: "What kind of tree can you carry in your hand?", answer: "A palm"),
        Riddle(question: "Which word in the dictionary is spelled incorrectly?", answer: "Incorrectly"),
        Riddle(question: "If an electric train is moving north at 100mph and a wind is blowing west at 10mph, which way does the smoke blow?", answer: "There is no smoke (it's an electric train!)"),
        Riddle(question: "How many months have 28 days?", answer: "All 12"),
        Riddle(question: "What can you hear, but not see or touch, even though you control it?", answer: "Your voice"),
        Riddle(question: "I have cities, but no houses. I have mountains, but no trees. I have water, but no fish. What am I?", answer: "A map"),
        Riddle(question: "What is always coming, but never arrives?", answer: "Tomorrow"),
        Riddle(question: "What can you break without picking it up?", answer: "A promise"),
        Riddle(question: "What has a thumb and four fingers but is not alive?", answer: "A glove"),
        Riddle(question: "What has 88 keys but can't open a single door?", answer: "A piano"),
        Riddle(question: "What has a heart but no other organs?", answer: "A deck of cards"),
        Riddle(question: "What has an eye but cannot see?", answer: "A needle"),
        Riddle(question: "What gets wetter the more it dries?", answer: "A towel"),
        Riddle(question: "What belongs to you but others use it more?", answer: "Your name"),
        Riddle(question: "I have keys but no locks. I have a space but no room. You can enter, but can\u{2019}t leave. What am I?", answer: "A keyboard"),
        Riddle(question: "What can you hear, but not see or touch?", answer: "Your voice"),
        Riddle(question: "What has 88 keys but can't open a door?", answer: "A piano")
    ]
}
