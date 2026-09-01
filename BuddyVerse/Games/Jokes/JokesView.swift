import SwiftUI

/// Mirrors JokesActivity: shows a joke, hides the punchline until "Reveal
/// Punchline" is tapped, and "Get Another Joke" draws the next one from a
/// shuffled bag (so jokes don't repeat until the whole pool has been shown
/// once, then it reshuffles and keeps going).
///
/// Turn-based for two people passing the phone: each player gets a batch of
/// 5 jokes, then it automatically hands off to the other player, forever -
/// there's no "round" that ends, just an alternating batch counter.
struct JokesView: View {
    struct Joke: Hashable {
        let setup: String
        let punchline: String
    }

    private static let batchSize = 5

    let selection: GameSelection
    @EnvironmentObject private var router: Router

    private enum Phase {
        case playing
        case handoff
    }

    private let pool: [Joke]
    @State private var remaining: [Joke]
    @State private var current: Joke
    @State private var showPunchline = false
    @State private var currentPlayer = 1
    @State private var jokesThisBatch = 1
    @State private var phase: Phase = .playing

    init(selection: GameSelection) {
        self.selection = selection
        let pool = Self.buildPool(from: selection.aiItems)
        self.pool = pool
        var shuffled = pool.shuffled()
        let first = shuffled.isEmpty ? Joke(setup: "Tap the button for a joke!", punchline: "") : shuffled.removeLast()
        _remaining = State(initialValue: shuffled)
        _current = State(initialValue: first)
    }

    // activity_jokes.xml: solid #4CAF50 background, no dark-mode override, so
    // this looks identical regardless of the app's theme setting.
    private let screenBg = Color(hex: 0x4CAF50)
    private let punchlineColor = Color(hex: 0xFFF59D)
    private let revealButtonBg = Color(hex: 0xFFC107)
    private let buttonTextDark = Color(hex: 0x333333)
    // #AADDDDDD - a light gray at ~67% alpha, not plain white-with-opacity.
    private let backButtonBg = Color(hex: 0xDDDDDD, opacity: 170.0 / 255.0)

    var body: some View {
        ZStack {
            screenBg.ignoresSafeArea()

            switch phase {
            case .playing: playingView
            case .handoff: handoffView
            }
        }
        .navigationBarHidden(true)
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
            Text("Get ready for the next batch of jokes.")
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
        }
        .padding(.horizontal, 20)
    }

    private var playingView: some View {
            // Root LinearLayout uses android:gravity="center", which centers
            // the whole content block vertically (not just top-aligned).
            VStack(spacing: 0) {
                Text("Jokes")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                Text("Player \(currentPlayer)'s Turn")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(punchlineColor)
                    .padding(.bottom, 4)

                Text("Joke \(jokesThisBatch) of \(Self.batchSize)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 30)

                Text(current.setup)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .padding(.bottom, 15)

                Text(current.punchline)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(punchlineColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .opacity(showPunchline ? 1 : 0)
                    .padding(.bottom, 40)

                // Android's btnRevealPunchline is set to GONE (removed from
                // layout, not just hidden) once tapped.
                if !showPunchline {
                    Button {
                        showPunchline = true
                    } label: {
                        Text("Reveal Punchline")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(buttonTextDark)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(revealButtonBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                }

                Button {
                    showNextJoke()
                } label: {
                    Text("Get Another Joke")
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
            }
            .padding(.horizontal, 20)
    }

    private func showNextJoke() {
        if remaining.isEmpty {
            remaining = pool.shuffled()
        }
        current = remaining.removeLast()
        showPunchline = false

        jokesThisBatch += 1
        if jokesThisBatch > Self.batchSize {
            jokesThisBatch = 1
            currentPlayer = currentPlayer == 1 ? 2 : 1
            phase = .handoff
        }
    }

    // MARK: - Pool building

    private struct AiJoke: Decodable {
        let setup: String?
        let punchline: String?
    }

    private static func buildPool(from aiItems: [String]?) -> [Joke] {
        let aiJokes: [Joke] = (aiItems ?? []).compactMap { raw in
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(AiJoke.self, from: data) else { return nil }
            let setup = (obj.setup ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let punchline = (obj.punchline ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !setup.isEmpty, !punchline.isEmpty else { return nil }
            return Joke(setup: setup, punchline: punchline)
        }
        if !aiJokes.isEmpty { return aiJokes }
        return allJokes.map(splitJoke)
    }

    // Every built-in joke is written as "Setup? Punchline" - split on the
    // first question mark so we can hide the punchline until revealed.
    private static func splitJoke(_ raw: String) -> Joke {
        if let qIndex = raw.firstIndex(of: "?") {
            let setup = String(raw[...qIndex])
            let punchline = String(raw[raw.index(after: qIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return Joke(setup: setup, punchline: punchline)
        }
        return Joke(setup: raw, punchline: "")
    }

    // MARK: - Static fallback pool (used whenever AI generation isn't
    // available - ported verbatim from JokesActivity.kt's allJokes list, the
    // baseline content most users will actually see).
    private static let allJokes: [String] = [
        "Why don't scientists trust atoms? Because they make up everything!",
        "What do you call a fake noodle? An Impasta!",
        "Why did the scarecrow win an award? Because he was outstanding in his field!",
        "What do you call a belt made out of watches? A waist of time!",
        "Why don't skeletons fight each other? They don't have the guts.",
        "What do you call cheese that isn't yours? Nacho cheese.",
        "How do you organize a space party? You planet.",
        "Why did the stadium get hot after the game? All of the fans left.",
        "What do you call a pony with a cough? A little hoarse.",
        "Why did the math book look sad? Because it had too many problems.",
        "What do you call a fly without wings? A walk.",
        "Why can't you give Elsa a balloon? Because she will let it go.",
        "What did the ocean say to the beach? Nothing, it just waved.",
        "Why did the golfer wear two pairs of pants? In case he got a hole in one.",
        "What do you call a bear with no teeth? A gummy bear!",
        "Why did the computer go to the doctor? Because it had a virus!",
        "What kind of shoes do ninjas wear? Sneakers!",
        "Why did the chicken cross the playground? To get to the other slide.",
        "What do you call a pig that knows karate? A pork chop!",
        "Why was the equal sign so humble? Because he knew he wasn't greater than or less than anyone else.",
        "What do you call an elephant that doesn't matter? An irrelephant.",
        "Why did the tomato turn red? Because it saw the salad dressing!",
        "What do you call a snobbish criminal going down stairs? A condescending con descending.",
        "Why don't eggs tell jokes? They'd crack each other up.",
        "What did one plate say to the other? Dinner is on me.",
        "Why was six afraid of seven? Because seven eight nine!",
        "What do you call a snowman with a six pack? An abdominal snowman.",
        "Why don't some couples go to the gym? Because some relationships don't work out.",
        "What do you call a sleeping bull? A bulldozer.",
        "Why did the invisible man turn down the job offer? He couldn't see himself doing it.",
        "What did the finger say to the thumb? I'm in glove with you.",
        "Why did the spider get a job in IT? He was a great web designer.",
        "What do you call a dog that does magic tricks? A labracadabrador.",
        "Why did the picture go to jail? Because it was framed!",
        "What do you call a guy with no body and no nose? Nobody knows.",
        "Why don't scientists trust staircases? They're always up to something.",
        "What did the zero say to the eight? Nice belt!",
        "Why did the banana go to the doctor? He wasn't peeling well.",
        "What do you call a boomerang that doesn't come back? A stick.",
        "Why did the student eat his homework? Because the teacher said it was a piece of cake!",
        "What kind of music do planets listen to? Nep-tunes!",
        "Why did the clock go to the principal? It was tock-ing too much.",
        "What do you call a cow with no legs? Ground beef.",
        "Why did the tree go to the dentist? It needed a root canal.",
        "What do you call a fake stone in Ireland? A sham rock.",
        "Why did the man put his money in the freezer? He wanted cold hard cash.",
        "What do you call a deer with no eyes? No eye deer.",
        "Why did the robot go on vacation? To recharge his batteries.",
        "What do you call a bee that can't make up its mind? A maybe.",
        "Why did the barber win the race? He knew all the short cuts.",
        "What do you call a fish with no eyes? Fsh.",
        "Why did the belt go to jail? For holding up a pair of pants.",
        "What do you call a cow with two legs? Lean beef.",
        "Why did the cookie go to the hospital? Because he felt crumb-y.",
        "What do you call a group of unorganized cats? A cat-astrophe.",
        "Why did the strawberry cross the road? Because his mom was in a jam.",
        "What do you call a sleeping pizza? A pi-z-z-z-a.",
        "Why did the man run around his bed? To catch up on his sleep.",
        "What do you call a dog in the winter? A chili dog.",
        "Why did the orange stop in the middle of the road? It ran out of juice.",
        "What do you call a dinosaur with an extensive vocabulary? A thesaurus.",
        "Why did the candle get married? It found its perfect match.",
        "What do you call a sheep with no legs? A cloud.",
        "Why did the boy bring a ladder to school? He wanted to go to high school.",
        "What do you call a funny mountain? Hill-arious.",
        "Why did the music teacher need a ladder? To reach the high notes.",
        "What do you call a fake surgery? A sham-poo.",
        "Why did the coffee file a police report? It got mugged.",
        "What do you call a bird that can't fly? A penguin (or a chicken!).",
        "Why did the math teacher go to the beach? To test the sine and cosine.",
        "What do you call a cow that plays an instrument? A moo-sician.",
        "Why did the man build his house out of cards? He wanted to have a deck.",
        "What do you call a cat that likes to bowl? An alley cat.",
        "Why did the golfer bring an extra pair of socks? In case he got a hole in one.",
        "What do you call a dog that likes to sunbathe? A hot dog.",
        "Why did the man put his car in the oven? He wanted a hot rod.",
        "What do you call a pig that is a thief? A ham-burglar.",
        "Why did the scarecrow win an award? He was out-standing in his field.",
        "What do you call a bear with no ears? B.",
        "Why did the man go to the movie theater? He wanted to see the big picture.",
        "What do you call a fish with no tail? A fishy.",
        "Why did the boy put his bed in the library? He wanted to sleep in the stacks.",
        "What do you call a bird that is a detective? A Sherlock Holmes-pigeon.",
        "Why did the man put his watch in the oven? He wanted to have a lot of time.",
        "What do you call a cow with a sense of humor? A laughing stock.",
        "Why did the boy bring a shovel to school? He wanted to dig up some knowledge.",
        "What do you call a fake tooth? A dental floss.",
        "Why did the man put his money in the blender? He wanted to make some liquid assets.",
        "What do you call a dog that is a computer expert? A cyber-spaniel.",
        "Why did the boy bring a flashlight to school? He wanted to be bright.",
        "What do you call a fake story? A tall tale.",
        "Why did the man put his shoes in the fridge? He wanted to have cool feet.",
        "What do you call a pig that is an artist? Pig-asso.",
        "Why did the boy bring a compass to school? He wanted to find his way.",
        "What do you call a fake flower? A sham-rock.",
        "Why did the man put his phone in the oven? He wanted to have a hot line.",
        "What do you call a cow that is a doctor? A moo-dical professional.",
        "Why did the boy bring a ruler to school? He wanted to measure up.",
        "What do you call a fake ID? A pseudo-nym.",
        "Why did the man put his hat in the freezer? He wanted to have a cool head.",
        "What do you call a pig that is a scientist? A lab-rat.",
        "Why did the boy bring a map to school? He wanted to know where he was going.",
        "What do you call a fake diamond? A cubic zirconium.",
        "Why did the man put his socks in the toaster? He wanted to have warm toes."
    ]
}
