import SwiftUI

/// Mirrors WelcomeActivity/activity_welcome.xml pixel-for-pixel where SwiftUI
/// allows it: same copy, same colors (including the exact light/dark swaps
/// from colors.xml/values-night/colors.xml and the drawable-night gradient
/// background), same section order. MainActivity's WebView wrapper is
/// reachable via "Visit Website ->" and is otherwise unrelated to this flow.
struct WelcomeView: View {
    @EnvironmentObject private var router: Router
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var systemScheme
    @State private var statJokes = 0
    @State private var statRiddles = 0
    @State private var statTrivia = 0
    @State private var statGames = 0
    @State private var scrollProxy: ScrollViewProxy?

    private var isDark: Bool { theme.isDarkActive(systemScheme: systemScheme) }

    // MARK: - Colors (exact hex values from colors.xml / values-night/colors.xml)

    private var headingColor: Color { isDark ? .white : Color(hex: 0x1A237E) }
    private var subtitleColor: Color { isDark ? Color(hex: 0xE0F7FA) : Color(hex: 0x283593) }
    private var bodyTextColor: Color { isDark ? Color(hex: 0xE0F7FA) : Color(hex: 0x333333) }
    private var bulletColor: Color { isDark ? .white : Color(hex: 0x333333) }
    private var statNumberColor: Color { isDark ? .white : Color(hex: 0x1A237E) }
    private var statLabelColor: Color { isDark ? Color(hex: 0xB2EBF2) : .black }
    private var sectionTealColor: Color { isDark ? Color(hex: 0xB2EBF2) : Color(hex: 0x00838F) }
    private var sectionDarkColor: Color { isDark ? .white : Color(hex: 0x333333) }
    private var exploreButtonBg: Color { isDark ? .white : Color(hex: 0x42A5F5) }
    // premium_card_background.xml swaps to a deeper maroon in dark mode instead of bright pink.
    private var premiumCardBg: Color { isDark ? Color(hex: 0x4A0E2E) : Color(hex: 0xE91E63) }
    // connect_card_background.xml / the free-games green have no drawable-night override - same in both modes.
    private let connectCardBg = Color(hex: 0x03A9F4)
    private let freeGameCardBg = Color(hex: 0x4CAF50)
    private let premiumHeaderColor = Color(hex: 0xFFC107)
    // card_background.xml: solid #8A000000 - used for stat tiles and the floating pill buttons, same in both modes.
    private let overlayCardBg = Color.black.opacity(0x8A / 255.0)
    private let bottomBarBg = Color.black.opacity(0x99 / 255.0)

    private let connectGames: [(emoji: String, title: String, subtitle: String, gameType: String)] = [
        ("😄", "Jokes", "Tell a quick joke to get a laugh and break the silence.", "JOKES"),
        ("🤔", "Riddles", "Stump a new friend, then enjoy the \u{201C}aha!\u{201D} together.", "RIDDLES"),
        ("🧠", "Trivia", "Surprising facts you can share \u{2014} and maybe change a mind.", "TRIVIA"),
        ("💬", "Conversation Starters", "Pick a side, say why. See what everyone else thinks.", "CONVERSATION")
    ]

    private let freeGames: [(emoji: String, title: String, subtitle: String, gameType: String)] = [
        ("❌", "Tic-Tac-Toe", "Classic 3-in-a-row vs. the computer.", "TICTACTOE"),
        ("✊", "Rock Paper Scissors", "Best of 5 against the computer.", "RPS"),
        ("🔢", "Sudoku", "Fill the grid 1\u{2013}9. Three difficulty levels.", "SUDOKU"),
        ("🧭", "Amazing Maze", "Find your way from start to finish. Arrows, WASD, or swipe.", "MAZE"),
        ("✋", "Count to 21", "Don't be the one to say 21! Learn the secret trick.", "COUNT21"),
        ("🔤", "Word Search", "Find the hidden words. Pick a new theme any time.", "WORDSEARCH"),
        ("🧩", "Memory Match", "Flip the cards and find every pair.", "MEMORY"),
        ("🎵", "Memory Sequence", "Watch & repeat the growing pattern.", "SEQUENCE"),
        ("🔀", "Slide Puzzle", "Slide the numbers back into order.", "SLIDE"),
        ("🪢", "Hangman", "Guess the word before the stickman is made.", "HANGMAN"),
        ("⚡", "Math Sprint", "Beat the clock with mental math. 3 levels.", "MATH")
    ]

    private let premiumGames: [(title: String, gameType: String, comingSoon: Bool)] = [
        ("Space Explorer 🚀", "SPACE", false), ("Jungle Run 🐒", "JUNGLE", false), ("Ocean Dive 🌊", "OCEAN", false),
        ("Mountain Climb 🏔️", "MOUNTAIN", false), ("Desert Trek 🏜️", "DESERT", false), ("Volcano Climb 🌋", "VOLCANO", false),
        ("Arctic Trek", "ARCTIC", false), ("Savanna Safari 🦁", "SAVANNA", false), ("Cave Explorer 🕯️", "CAVE", false),
        ("Swamp Trek 🐊", "SWAMP", false), ("Storm Chase ⚡", "STORM", false),
        ("Canyon Zipline 🪂 (Coming Soon)", "CANYON_ZIPLINE", true), ("Meteor Shower ☄️ (Coming Soon)", "METEOR_SHOWER", true)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            rootBackground

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header.frame(maxWidth: .infinity)
                        exploreBlock
                        mainSections
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 100)
                }
                .onAppear {
                    scrollProxy = proxy
                    animateStats()
                    // Only ever fires once, right at cold launch (this
                    // ScrollViewReader is part of WelcomeView's permanent
                    // base screen, never re-mounted) - so a signed-in admin
                    // lands on AdminHomeView automatically every time they
                    // open the app, without needing to tap anything first.
                    if AuthManager.isAdmin() && router.path.isEmpty {
                        router.push(.adminHome)
                    }
                }
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
        }
        .navigationBarHidden(true)
    }

    private var rootBackground: some View {
        Group {
            if isDark {
                LinearGradient(
                    colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                    startPoint: .bottomLeading, endPoint: .topTrailing
                )
            } else {
                Color.white
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Header + explore block

    private var header: some View {
        VStack(spacing: 0) {
            Text("BuddyVerse")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(headingColor)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 2, y: 2)
            Text("The Buddy Maker")
                .font(.system(size: 24))
                .italic()
                .foregroundColor(subtitleColor)
                .padding(.bottom, 15)
        }
        .multilineTextAlignment(.center)
    }

    private var exploreBlock: some View {
        VStack(spacing: 0) {
            Text("A friendly way to make friends")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(headingColor)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Button {
                withAnimation { scrollProxy?.scrollTo("connectSection", anchor: .top) }
            } label: {
                Text("Explore the app")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: 0x1A237E))
                    .padding(.horizontal, 40)
                    .frame(height: 60)
                    .background(exploreButtonBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .padding(.bottom, 20)

            Text("Make a friend today. New at school or sitting alone at lunch? Pick a joke, a riddle, a big question, or a game \u{2014} BuddyVerse makes saying \u{201C}hi\u{201D} a whole lot easier.")
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(bodyTextColor)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.bottom, 25)

            VStack(spacing: 4) {
                Text("✨ No sign up")
                Text("📱 Works on any device")
                Text("🎮 100% original games")
            }
            .font(.system(size: 18))
            .foregroundColor(bulletColor)
            .padding(.bottom, 25)

            statsGrid
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 25)
        .padding(.bottom, 15)
    }

    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard("\(statJokes)+", "Jokes")
                statCard("\(statRiddles)+", "Riddles")
            }
            HStack(spacing: 12) {
                statCard("\(statTrivia)+", "Trivia facts")
                statCard("\(statGames)", "Original games")
            }
        }
    }

    private func statCard(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 32, weight: .bold)).foregroundColor(statNumberColor)
            Text(label).font(.system(size: 15)).foregroundColor(statLabelColor).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(overlayCardBg))
    }

    // MARK: - Connect / Free Games / Premium sections

    private var mainSections: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connect Together (Without Games)")
                .id("connectSection")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(sectionTealColor)
                .padding(.bottom, 10)

            ForEach(Array(connectGames.enumerated()), id: \.element.gameType) { index, game in
                cardButton(
                    emoji: game.emoji, title: game.title, subtitle: game.subtitle,
                    subtitleColor: Color(hex: 0xE3F2FD), background: connectCardBg
                ) {
                    router.push(.moodSelection(gameType: game.gameType))
                }
                .padding(.bottom, index == connectGames.count - 1 ? 30 : 10)
            }

            Text("🎮 Connect Together With Games")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(sectionDarkColor)
                .padding(.bottom, 10)

            ForEach(Array(freeGames.enumerated()), id: \.element.gameType) { index, game in
                cardButton(
                    emoji: game.emoji, title: game.title, subtitle: game.subtitle,
                    subtitleColor: Color(hex: 0xE8F5E9), background: freeGameCardBg
                ) {
                    openFreeGame(game.gameType)
                }
                .padding(.bottom, index == freeGames.count - 1 ? 30 : 10)
            }

            Text("Premium Expeditions")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(premiumHeaderColor)
                .padding(.bottom, 10)

            ForEach(Array(premiumGames.enumerated()), id: \.element.gameType) { index, game in
                premiumButton(game.title) {
                    if game.comingSoon {
                        router.push(.comingSoon(gameName: game.title.replacingOccurrences(of: " (Coming Soon)", with: "")))
                    } else {
                        router.push(.lobby(gameType: game.gameType))
                    }
                }
                .padding(.bottom, index == premiumGames.count - 1 ? 20 : 10)
            }
        }
        .padding(.horizontal, 20)
    }

    private func cardButton(
        emoji: String, title: String, subtitle: String, subtitleColor: Color, background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(emoji) \(title)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(subtitleColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(background))
        }
        .buttonStyle(.plain)
    }

    private func premiumButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(premiumCardBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // Rock Paper Scissors is vs-the-bot only - skip straight to difficulty.
    // Math Sprint is solo-only - skip straight to round-length selection.
    // Everything else asks "with a friend?" first, matching Android exactly.
    private func openFreeGame(_ gameType: String) {
        switch gameType {
        case "RPS":
            router.push(.botDifficulty(gameType: "RPS"))
        case "MATH":
            router.push(.mathSprintSelection)
        default:
            router.push(.onePhoneSelection(gameType: gameType))
        }
    }

    // MARK: - Floating overlays (top pills + bottom bar, pinned outside the ScrollView like Android's FrameLayout)

    private var topBar: some View {
        HStack {
            pillButton("🎉 Credits") { router.push(.credits) }
            Spacer()
            pillButton(isDark ? "☀️ Light Mode" : "🌙 Dark Mode") { theme.toggle() }
        }
        .padding(16)
    }

    private func pillButton(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(overlayCardBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        ZStack {
            HStack {
                Button("Contact Us") { router.push(.contactUs) }
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Spacer()
                Button("Visit Website →") { router.push(.mainWebsite) }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            // Reads live from the app's own Info.plist (CFBundleShortVersionString,
            // set by MARKETING_VERSION in project.yml) rather than a hardcoded
            // string, so this label can never drift from what was actually
            // built - handy for confirming two test devices (e.g. an Android
            // device and an iOS simulator/iPad) are running the same build.
            VStack(spacing: 2) {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                // Low-key on purpose - this is only ever needed the first
                // time on a new device (or after signing out); a returning
                // admin session already gets carried straight to
                // AdminHomeView on launch, so this never needs to be
                // prominent.
                Button("Log In") { router.push(.login) }
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(bottomBarBg)
        .ignoresSafeArea(edges: .bottom)
    }

    // Mirrors WelcomeActivity.animateCountUp: counts 0 -> target over 1.5s with
    // a decelerate (ease-out) curve, same 18 hardcoded "Original games" total.
    private func animateStats() {
        animateCountUp(target: 100) { statJokes = $0 }
        animateCountUp(target: 100) { statRiddles = $0 }
        animateCountUp(target: 100) { statTrivia = $0 }
        animateCountUp(target: 18) { statGames = $0 }
    }

    private func animateCountUp(target: Int, duration: Double = 1.5, update: @escaping (Int) -> Void) {
        let steps = 30
        let interval = duration / Double(steps)
        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(step)) {
                let t = Double(step) / Double(steps)
                let eased = 1 - (1 - t) * (1 - t) // DecelerateInterpolator-style ease-out
                update(Int(Double(target) * eased))
            }
        }
    }
}
