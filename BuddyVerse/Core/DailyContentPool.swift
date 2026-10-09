import Foundation

/// A small "pick of the day" pool shared between the main app and the
/// BuddyVerseWidget home-screen widget (see DailyContentWidget.swift). This
/// has to be its own file rather than reusing JokesView.allJokes /
/// RiddlesView.allRiddles directly, for the same reason
/// BuddyVerseActivityAttributes.swift lives here and not under Games/ - the
/// widget extension is a separate compilation target and can't see the main
/// app target's files, so it's listed under both targets' `sources` in
/// project.yml instead. This is a smaller, curated subset of the full
/// in-game pools (not the whole ~100-entry lists) - plenty of variety for a
/// once-a-day pick without bloating the widget extension's binary.
enum DailyContentPool {
    enum Kind {
        case joke
        case riddle
    }

    struct Pick {
        let kind: Kind
        /// Joke setup / riddle question - always shown.
        let primary: String
        /// Joke punchline / riddle answer - hidden behind "Tap to reveal"
        /// framing in the widget UI, shown in full once the app opens.
        let secondary: String
    }

    /// Deterministic per-day pick: the same calendar day (in the device's
    /// current time zone) always resolves to the same entry, so a widget's
    /// placeholder/snapshot/timeline-entry renders never disagree with each
    /// other within one day, and the pick only changes at local midnight.
    /// Alternates joke/riddle by day-of-year parity so consecutive days
    /// differ in kind, not just content.
    static func pick(for date: Date) -> Pick {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        if dayOfYear % 2 == 0 {
            let (setup, punchline) = splitJoke(jokes[dayOfYear % jokes.count])
            return Pick(kind: .joke, primary: setup, secondary: punchline)
        } else {
            let riddle = riddles[dayOfYear % riddles.count]
            return Pick(kind: .riddle, primary: riddle.question, secondary: riddle.answer)
        }
    }

    // Every joke below is written "Setup? Punchline" (same convention as
    // JokesView.allJokes) - split on the first question mark.
    private static func splitJoke(_ raw: String) -> (setup: String, punchline: String) {
        guard let qIndex = raw.firstIndex(of: "?") else { return (raw, "") }
        let setup = String(raw[...qIndex])
        let punchline = String(raw[raw.index(after: qIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (setup, punchline)
    }

    // MARK: - Curated subset (30 of each, pulled verbatim from
    // JokesView.allJokes / RiddlesView.allRiddles).

    private static let jokes: [String] = [
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
        "What do you call an elephant that doesn't matter? An irrelephant.",
        "Why did the tomato turn red? Because it saw the salad dressing!",
        "Why don't eggs tell jokes? They'd crack each other up.",
        "What did one plate say to the other? Dinner is on me.",
        "Why was six afraid of seven? Because seven eight nine!",
        "What do you call a snowman with a six pack? An abdominal snowman.",
        "What do you call a sleeping bull? A bulldozer.",
        "Why did the invisible man turn down the job offer? He couldn't see himself doing it.",
        "What did the finger say to the thumb? I'm in glove with you.",
        "Why did the spider get a job in IT? He was a great web designer.",
        "What do you call a dog that does magic tricks? A labracadabrador."
    ]

    private static let riddles: [(question: String, answer: String)] = [
        ("What has hands but can't clap?", "A clock"),
        ("What has to be broken before you can use it?", "An egg"),
        ("What has one eye but can't see?", "A needle"),
        ("What has legs but doesn't walk?", "A table"),
        ("What has a neck but no head?", "A bottle"),
        ("What is full of holes but still holds water?", "A sponge"),
        ("What is always in front of you but can\u{2019}t be seen?", "The future"),
        ("What can you break, even if you never pick it up or touch it?", "A promise"),
        ("What goes up but never comes down?", "Your age"),
        ("What has many keys but can\u{2019}t open a single lock?", "A piano"),
        ("What has a thumb and four fingers, but is not a hand?", "A glove"),
        ("What gets wet while drying?", "A towel"),
        ("What can you keep after giving it to someone?", "Your word"),
        ("What has words, but never speaks?", "A book"),
        ("What runs but has no legs?", "A river"),
        ("What is black when it\u{2019}s clean and white when it\u{2019}s dirty?", "A chalkboard"),
        ("What belongs to you, but others use it more than you do?", "Your name"),
        ("I\u{2019}m tall when I\u{2019}m young, and I\u{2019}m short when I\u{2019}m old. What am I?", "A candle"),
        ("What can travel around the world while staying in a corner?", "A stamp"),
        ("What has a head and a tail but no body?", "A coin"),
        ("What building has the most stories?", "A library"),
        ("The more of this there is, the less you see. What is it?", "Darkness"),
        ("What has a bottom at the top?", "Your legs"),
        ("What can you catch but not throw?", "A cold"),
        ("What kind of room has no doors or windows?", "A mushroom"),
        ("What has a heart that doesn\u{2019}t beat?", "An artichoke"),
        ("I follow you all day long, but when the night comes, I\u{2019}m gone. What am I?", "Your shadow"),
        ("What gets sharper the more you use it?", "Your brain"),
        ("What is easy to get into but hard to get out of?", "Trouble"),
        ("What can fill a room but takes up no space?", "Light")
    ]
}
