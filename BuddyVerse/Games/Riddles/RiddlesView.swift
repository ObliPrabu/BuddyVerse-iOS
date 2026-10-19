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
        let pool = Self.allRiddles
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

    // MARK: - Built-in riddle pool (the only content source - there is no AI
    // generation. Mood/age group intentionally don't scope it, so every entry
    // has to be all-ages-safe.)
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
        Riddle(question: "What can you catch but not throw?", answer: "A cold"),
        Riddle(question: "What kind of room has no doors or windows?", answer: "A mushroom"),
        Riddle(question: "What has a heart that doesn\u{2019}t beat?", answer: "An artichoke"),
        Riddle(question: "I follow you all day long, but when the night comes, I\u{2019}m gone. What am I?", answer: "Your shadow"),
        Riddle(question: "What gets sharper the more you use it?", answer: "Your brain"),
        Riddle(question: "I am always hungry, I must always be fed. The finger I touch, will soon turn red. What am I?", answer: "Fire"),
        Riddle(question: "What is easy to get into but hard to get out of?", answer: "Trouble"),
        Riddle(question: "What can fill a room but takes up no space?", answer: "Light"),
        Riddle(question: "If you drop me I\u{2019}m sure to crack, but give me a smile and I\u{2019}ll always smile back. What am I?", answer: "A mirror"),
        Riddle(question: "I\u{2019}m light as a feather, yet the strongest person can\u{2019}t hold me for five minutes. What am I?", answer: "Breath"),
        Riddle(question: "What is so fragile that saying its name breaks it?", answer: "Silence"),
        Riddle(question: "What can you hold in your left hand but not in your right?", answer: "Your right elbow"),
        Riddle(question: "What has many teeth, but cannot bite?", answer: "A comb"),
        Riddle(question: "What starts with T, ends with T, and has T in it?", answer: "A teapot"),
        Riddle(question: "What kind of tree can you carry in your hand?", answer: "A palm"),
        Riddle(question: "Which word in the dictionary is spelled incorrectly?", answer: "Incorrectly"),
        Riddle(question: "If an electric train is moving north at 100mph and a wind is blowing west at 10mph, which way does the smoke blow?", answer: "There is no smoke (it's an electric train!)"),
        Riddle(question: "How many months have 28 days?", answer: "All 12"),
        Riddle(question: "What can you hear, but not see or touch, even though you control it?", answer: "Your voice"),
        Riddle(question: "What is always coming, but never arrives?", answer: "Tomorrow"),
        Riddle(question: "I have keys but no locks. I have a space but no room. You can enter, but can\u{2019}t leave. What am I?", answer: "A keyboard"),
        Riddle(question: "What has a ring but no finger?", answer: "A telephone"),
        Riddle(question: "What goes through towns and fields but never moves?", answer: "A road"),
        Riddle(question: "What has four wheels and flies?", answer: "A garbage truck"),
        Riddle(question: "What goes up when the rain comes down?", answer: "An umbrella"),
        Riddle(question: "What has one head, one foot and four legs?", answer: "A bed"),
        Riddle(question: "What comes down but never goes up?", answer: "Rain"),
        Riddle(question: "What is at the end of a rainbow?", answer: "The letter W"),
        Riddle(question: "What begins with an E but only has one letter?", answer: "An envelope"),
        Riddle(question: "What word becomes shorter when you add two letters to it?", answer: "Short"),
        Riddle(question: "What can you hold without ever touching it?", answer: "A conversation"),
        Riddle(question: "What has a tongue but cannot talk?", answer: "A shoe"),
        Riddle(question: "What gets bigger the more you take away from it?", answer: "A hole"),
        Riddle(question: "What flies without wings?", answer: "Time"),
        Riddle(question: "What can’t talk but will answer when spoken to?", answer: "An echo"),
        Riddle(question: "What is easy to lift but hard to throw?", answer: "A feather"),
        Riddle(question: "What is made of water but disappears if you put it in water?", answer: "Ice"),
        Riddle(question: "What kind of band never plays music?", answer: "A rubber band"),
        Riddle(question: "What do you throw out when you want to use it, and take in when you don’t?", answer: "An anchor"),
        Riddle(question: "What kind of coat is always wet when you put it on?", answer: "A coat of paint"),
        Riddle(question: "What can be cracked, made, told and played?", answer: "A joke"),
        Riddle(question: "Where does today come before yesterday?", answer: "The dictionary"),
        Riddle(question: "What can you serve but never eat?", answer: "A tennis ball"),
        Riddle(question: "What type of cheese is made backwards?", answer: "Edam"),
        Riddle(question: "What flies around all day but never goes anywhere?", answer: "A flag"),
        Riddle(question: "I have branches, but no fruit, trunk or leaves. What am I?", answer: "A bank"),
        Riddle(question: "What goes up and down but never moves?", answer: "A staircase"),
        Riddle(question: "What lets you look right through a wall?", answer: "A window"),
        Riddle(question: "What runs around a yard without moving?", answer: "A fence"),
        Riddle(question: "What has no beginning, no end and no middle?", answer: "A circle"),
        Riddle(question: "What starts with P, ends with E and has thousands of letters?", answer: "The post office"),
        Riddle(question: "What do you see once in a minute, twice in a moment and never in a thousand years?", answer: "The letter M"),
        Riddle(question: "What kind of nut has no shell?", answer: "A doughnut"),
        Riddle(question: "What is in the middle of Paris?", answer: "The letter R"),
        Riddle(question: "What do cars and elephants both have?", answer: "Trunks"),
        Riddle(question: "What loses its head in the morning and gets it back at night?", answer: "A pillow"),
        Riddle(question: "What is the longest word in the dictionary?", answer: "Smiles, because there’s a mile between the first and last letters"),
        Riddle(question: "What kind of cup can’t hold water?", answer: "A cupcake"),
        Riddle(question: "What is bigger than the Eiffel Tower but weighs nothing?", answer: "Its shadow"),
        Riddle(question: "What can you make that no one can see?", answer: "Noise"),
        Riddle(question: "What goes through a door but never goes in or out?", answer: "A keyhole"),
        Riddle(question: "What has no life but can die?", answer: "A battery"),
        Riddle(question: "Forward I am heavy, but backward I am not. What am I?", answer: "Ton"),
        Riddle(question: "What tastes better than it smells?", answer: "Your tongue"),
        Riddle(question: "What is a witch’s favorite subject in school?", answer: "Spelling"),
        Riddle(question: "What type of music do rabbits like?", answer: "Hip hop"),
        Riddle(question: "What always sleeps with its shoes on?", answer: "A horse"),
        Riddle(question: "What has one horn and gives milk?", answer: "A milk truck"),
        Riddle(question: "Which weighs more, a pound of feathers or a pound of bricks?", answer: "They weigh the same"),
        Riddle(question: "How far can a dog run into the woods?", answer: "Halfway - after that it’s running out"),
        Riddle(question: "How many seconds are there in a year?", answer: "Twelve - January 2nd, February 2nd, and so on"),
        Riddle(question: "What has six faces but doesn’t wear any makeup?", answer: "A die"),
        Riddle(question: "What is orange and sounds like a parrot?", answer: "A carrot"),
        Riddle(question: "What is black and white and read all over?", answer: "A newspaper"),
        Riddle(question: "What has 13 hearts but no other organs?", answer: "A deck of cards"),
        Riddle(question: "What has a thumb but no other fingers?", answer: "A mitten"),
        Riddle(question: "What is always in front of you but can’t be seen?", answer: "The future"),
        Riddle(question: "What has many keys but can’t open a single lock?", answer: "A piano"),
        Riddle(question: "What is black when it’s clean and white when it’s dirty?", answer: "A chalkboard"),
        Riddle(question: "I’m tall when I’m young, and I’m short when I’m old. What am I?", answer: "A candle"),
        Riddle(question: "What has a heart that doesn’t beat?", answer: "An artichoke"),
        Riddle(question: "I follow you all day long, but when the night comes, I’m gone. What am I?", answer: "Your shadow"),
        Riddle(question: "If you drop me I’m sure to crack, but give me a smile and I’ll always smile back. What am I?", answer: "A mirror"),
        Riddle(question: "I’m light as a feather, yet the strongest person can’t hold me for five minutes. What am I?", answer: "Breath"),
        Riddle(question: "I have keys but no locks. I have a space but no room. You can enter, but can’t leave. What am I?", answer: "A keyboard"),
    ]
}
