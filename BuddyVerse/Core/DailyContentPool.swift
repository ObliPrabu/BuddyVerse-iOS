import Foundation

/// A small "pick of the day" pool shared between the main app and the
/// BuddyVerseWidget home-screen widget (see DailyContentWidget.swift). This
/// has to be its own file rather than reusing JokesView.allJokes /
/// RiddlesView.allRiddles directly, for the same reason
/// BuddyVerseActivityAttributes.swift lives here and not under Games/ - the
/// widget extension is a separate compilation target and can't see the main
/// app target's files, so it's listed under both targets' `sources` in
/// project.yml instead. This is a smaller, curated list (not the whole
/// ~100-entry in-game pools) - plenty of variety for a once-a-day pick
/// without bloating the widget extension's binary.
///
/// The entries were first taken from the in-game pools (JokesView,
/// RiddlesView, TriviaView), so the two mostly overlap, but this is a
/// separate hand-kept copy rather than a strict subset: edits to the in-game
/// pools don't carry over by themselves, so an entry here may be worded
/// differently from its in-game twin or may be one the in-game pool has since
/// retired (the sleeping-bull joke is one). Don't "sync" such an entry by
/// dropping it: removing or adding an entry changes what most days show (the
/// index is `% count`), so any change to a list has to be made at the same
/// position in Android's DailyContentPool.kt in the same step.
enum DailyContentPool {
    enum Kind {
        case joke
        case riddle
        case trivia
    }

    struct Pick {
        let kind: Kind
        /// Joke setup / riddle or trivia question - always shown.
        let primary: String
        /// Joke punchline / riddle or trivia answer - shown in full on
        /// the in-app Question of the Day screen.
        let secondary: String
    }

    // On a holiday the daily pick is always that holiday's riddle, whatever the
    // normal rotation would have chosen. Keyed by month * 100 + day (month
    // 1-12). Thanksgiving (the 4th Thursday of November) moves, so it is
    // worked out separately. Android's DailyContentPool.kt has the identical
    // list; keep them in sync.
    private static let holidayRiddles: [Int: Pick] = [
        101: Pick(kind: .riddle, primary: "I come once a year, I have twelve months, and everyone says \"Happy\" to me when I start. What am I?", secondary: "A new year"),
        214: Pick(kind: .riddle, primary: "I beat all day without a drum, and I'm the shape on every Valentine's card. What am I?", secondary: "A heart"),
        317: Pick(kind: .riddle, primary: "I'm a little green plant with three leaves, and finding a four-leaf one is said to bring luck. What am I?", secondary: "A clover"),
        422: Pick(kind: .riddle, primary: "I'm round and blue and green, and everyone you know lives on me. What am I?", secondary: "The Earth"),
        704: Pick(kind: .riddle, primary: "I light up the night sky with colors and a bang on the Fourth of July. What am I?", secondary: "Fireworks"),
        1031: Pick(kind: .riddle, primary: "I wear a carved smile and a candle glows inside me, but I'm not a person. What am I?", secondary: "A jack-o'-lantern"),
        1224: Pick(kind: .riddle, primary: "I wear a red suit, my sleigh is pulled by reindeer, and I visit on Christmas Eve. Who am I?", secondary: "Santa Claus"),
        1225: Pick(kind: .riddle, primary: "I'm covered in lights and ornaments and I stand in the living room in December. What am I?", secondary: "A Christmas tree"),
        1231: Pick(kind: .riddle, primary: "At midnight everyone counts me down, and when I reach zero a new year begins. What am I?", secondary: "A countdown"),
    ]
    private static let thanksgivingRiddle = Pick(kind: .riddle, primary: "I say \"gobble gobble\" and I'm the star of the Thanksgiving feast. What am I?", secondary: "A turkey")

    private static func holidayPick(for date: Date) -> Pick? {
        let c = Calendar.current.dateComponents([.month, .day, .weekday], from: date)
        guard let month = c.month, let day = c.day else { return nil }
        if month == 11, c.weekday == 5, (22...28).contains(day) { return thanksgivingRiddle }
        return holidayRiddles[month * 100 + day]
    }

    /// Deterministic per-day pick: the same calendar day (in the device's
    /// current time zone) always resolves to the same entry, so a widget's
    /// placeholder/snapshot/timeline-entry renders never disagree with each
    /// other within one day, and the pick only changes at local midnight.
    /// Rotates joke/riddle/trivia by `dayOfYear % 3` and steps through each
    /// pool by `dayOfYear / 3` (indexing with `% 30` too would only ever
    /// reach 10 of each pool's 30 entries). Android's DailyContentPool.kt
    /// uses the same rule and entry order.
    static func pick(for date: Date) -> Pick {
        if let holiday = holidayPick(for: date) { return holiday }
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        switch dayOfYear % 3 {
        case 0:
            let (setup, punchline) = splitJoke(jokes[(dayOfYear / 3) % jokes.count])
            return Pick(kind: .joke, primary: setup, secondary: punchline)
        case 1:
            let riddle = riddles[(dayOfYear / 3) % riddles.count]
            return Pick(kind: .riddle, primary: riddle.question, secondary: riddle.answer)
        default:
            let q = trivia[(dayOfYear / 3) % trivia.count]
            return Pick(kind: .trivia, primary: q.question, secondary: q.answer)
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

    // MARK: - Curated lists (30 of each). Entries were taken from the
    // in-game pools (JokesView/RiddlesView/TriviaView) and may drift from
    // them after later pool edits; what must stay identical is Android's
    // DailyContentPool.kt (same entries, same order).

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
        "What kind of key opens a banana? A monkey!",
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
        ("What has 13 hearts but no other organs?", "A deck of cards"),
        ("What can you catch but not throw?", "A cold"),
        ("What kind of room has no doors or windows?", "A mushroom"),
        ("What has a heart that doesn\u{2019}t beat?", "An artichoke"),
        ("I follow you all day long, but when the night comes, I\u{2019}m gone. What am I?", "Your shadow"),
        ("What gets sharper the more you use it?", "Your brain"),
        ("What is easy to get into but hard to get out of?", "Trouble"),
        ("What can fill a room but takes up no space?", "Light")
    ]

    private static let trivia: [(question: String, answer: String)] = [
        ("What is the capital of France?", "Paris"),
        ("Which planet is known as the Red Planet?", "Mars"),
        ("What is 5 x 5?", "25"),
        ("Who painted the Mona Lisa?", "Da Vinci"),
        ("Which ocean is the largest?", "Pacific"),
        ("What is the fastest land animal?", "Cheetah"),
        ("In the common 7-continent model, how many continents are there?", "7"),
        ("What is the hardest natural substance?", "Diamond"),
        ("What do bees collect from flowers?", "Nectar"),
        ("What is the freezing point of water?", "0\u{00B0}C"),
        ("What is the square root of 64?", "8"),
        ("Who wrote 'Romeo and Juliet'?", "Shakespeare"),
        ("What is the chemical symbol for gold?", "Au"),
        ("Which planet is closest to the Sun?", "Mercury"),
        ("How many colors are in a rainbow?", "7"),
        ("What is the largest organ in the human body?", "Skin"),
        ("Which gas do plants absorb from the atmosphere?", "Carbon Dioxide"),
        ("What is the capital of Japan?", "Tokyo"),
        ("How many teeth does a full adult set have, including wisdom teeth?", "32"),
        ("What is the study of stars called?", "Astronomy"),
        ("What is the tallest mountain in the world?", "Everest"),
        ("Who was the first man to walk on the moon?", "Neil Armstrong"),
        ("What is the capital of Italy?", "Rome"),
        ("Which animal is known as the King of the Jungle?", "Lion"),
        ("What is the chemical formula for water?", "H2O"),
        ("How many days are in a leap year?", "366"),
        ("What is the primary language spoken in Brazil?", "Portuguese"),
        ("Which planet is famous for its rings?", "Saturn"),
        ("What is the smallest prime number?", "2"),
        ("Who is most famously credited with inventing the practical light bulb?", "Edison")
    ]
}
