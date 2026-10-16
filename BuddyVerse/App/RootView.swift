import SwiftUI

/// Owns the navigation path. Screens push forward with `path.append(.someRoute)`;
/// every screen's own manual "Back" button calls `router.pop()` to pop
/// exactly one level - a deliberate departure from the Android app's literal
/// behavior (every intermediate screen calls `startActivity()+finish()`, so
/// its back stack always collapses straight to Welcome). Standard push/pop
/// is what iOS users expect from a back button.
///
/// This used to be a real `NavigationStack(path:)`, but that (and
/// `@Environment(\.dismiss)`, and `.navigationDestination(for:)`) requires
/// iOS 16+. The app supports iOS 14+, so RootView instead renders `path`
/// itself as a stack of views in a plain `ZStack` (see below) - `Router`'s
/// public API (`push`/`pop`/`popToRoot`/`replaceTop`) is unchanged, so no
/// screen needs to know or care which one is backing it.
final class Router: ObservableObject {
    @Published var path: [AppRoute] = []

    func push(_ route: AppRoute) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }

    /// For purely automatic, no-user-choice screens (e.g. the "Using AI..."
    /// loading screen) that shouldn't leave a stray, back-button-hidden
    /// entry sitting in the stack once they've moved on.
    func replaceTop(with route: AppRoute) {
        if path.isEmpty { path.append(route) } else { path[path.count - 1] = route }
    }

    /// Drops the premium Lobby entry AND every screen above it (the Account
    /// and payment screens a purchase passes through), then puts `route` in
    /// their place. A purchase or entitlement hand-off used to replace only
    /// the topmost screen, which left the Lobby sitting underneath - so
    /// pressing Back from the game picker showed the "Unlock Premium Access"
    /// paywall again to someone who had already paid.
    func replaceLobby(with route: AppRoute) {
        let lobbyIndex = path.lastIndex(where: { if case .lobby = $0 { return true } else { return false } })
        if let lobbyIndex {
            path.removeSubrange(lobbyIndex...)
            path.append(route)
        } else {
            replaceTop(with: route)
        }
    }
}

struct RootView: View {
    @StateObject private var router = Router()

    // The mandatory, first-launch-only name gate (EnterNameView, then
    // GetUpdatesView) - rendered as an overlay on top of the already-mounted
    // content below rather than a pushed route, mirroring Android's
    // WelcomeActivity/EnterNameActivity relationship: the content underneath
    // is already fully live the whole time, so once `hasEnteredName` flips
    // to true it's simply revealed - no relaunch, no blank-state risk.
    @State private var hasEnteredName = UserDefaults.standard.bool(forKey: "has_entered_name")
    @State private var gateShowsUpdatesStep = false

    // Widget/URL-scheme deep links (buddyverse://daily/...) land here via
    // DeepLinkManager rather than directly on `router`, since Router is
    // scoped to this view - see that file's own doc comment.
    @ObservedObject private var deepLink = DeepLinkManager.shared

    var body: some View {
        ZStack {
            mainContent
                .allowsHitTesting(hasEnteredName)

            if !hasEnteredName {
                gateOverlay
                    .zIndex(1000)
            }
        }
        .environmentObject(router)
        .onChange(of: deepLink.pendingRoute) { _ in consumePendingDeepLink() }
        // A link that arrived while the name gate was still up is held until
        // the gate is done; one that landed before this view was observing
        // (cold launch) is picked up on appear.
        .onChange(of: hasEnteredName) { _ in consumePendingDeepLink() }
        .onAppear { consumePendingDeepLink() }
    }

    private func consumePendingDeepLink() {
        guard hasEnteredName, let route = deepLink.pendingRoute else { return }
        deepLink.pendingRoute = nil
        // Replacing the path drops every screen without running its Back
        // handler, so a live room has to be ended here or the other players
        // hang until the heartbeat times out (same leak ISSUE-43 closed for
        // Back).
        if router.path.contains(where: Self.holdsOnlineRoom) {
            InternetConnectionManager.shared.stop()
        }
        router.path = [route]
    }

    private static func holdsOnlineRoom(_ route: AppRoute) -> Bool {
        switch route {
        case .onlineLobby:
            return true
        case .hangmanModeChoice(let selection), .instructionsChoice(let selection),
             .instructionsView(let selection), .game(let selection):
            return selection.isNearby
        default:
            return false
        }
    }

    @ViewBuilder
    private var gateOverlay: some View {
        if gateShowsUpdatesStep {
            GetUpdatesView(onBack: { hasEnteredName = true })
        } else {
            EnterNameView(onContinue: { gateShowsUpdatesStep = true })
        }
    }

    private var mainContent: some View {
        // Every pushed screen stays mounted (indices are stable - push only
        // appends, pop only drops the last one) so a screen's @State
        // survives the player backing into it, roughly matching
        // NavigationStack's behavior. zIndex keeps later pushes on top;
        // the asymmetric transition gives the same push-right/pop-left slide
        // NavigationStack gives for free. Deliberately no edge-swipe-to-back
        // gesture here - every screen already renders its own visible Back
        // button (see AppRoute/RootView's destination(for:) below), and a
        // hand-rolled swipe gesture would risk fighting screens that already
        // have their own drag gestures (WordSearchView's selection drag,
        // MazeGameView's swipeGesture).
        //
        // CRITICAL: only the topmost screen may take touches.
        // `allowsHitTesting` below is not optional polish - without it every
        // fully-mounted-but-covered screen underneath still has live Buttons
        // sitting at the exact same full-screen frame as the visible one, and
        // a few levels deep (Welcome -> OnePhoneSelection -> BotDifficulty ->
        // InstructionsChoice -> Game is typical) that's 4-5 overlapping
        // interactive layers fighting over every tap - UIKit's gesture
        // recognizer arbitration can end up delivering the touch to none of
        // them, which is exactly why nothing was tappable in-game.
        ZStack {
            WelcomeView()
                .allowsHitTesting(router.path.isEmpty)
            ForEach(Array(router.path.enumerated()), id: \.offset) { index, route in
                destination(for: route)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .zIndex(Double(index + 1))
                    .allowsHitTesting(index == router.path.count - 1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: router.path.count)
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .mainWebsite:
            MainWebsiteView()
        case .ageGroup(let gameType, let mood, let difficulty):
            AgeGroupView(gameType: gameType, mood: mood, difficulty: difficulty)
        case .moodSelection(let gameType):
            MoodSelectionView(gameType: gameType)
        case .difficultySelection(let gameType, let mood):
            DifficultySelectionView(gameType: gameType, mood: mood)
        case .aiGenerating(let gameType, let mood, let ageGroup, let difficulty):
            AiGeneratingView(gameType: gameType, mood: mood, ageGroup: ageGroup, difficulty: difficulty)
        case .onePhoneSelection(let gameType):
            OnePhoneSelectionView(gameType: gameType)
        case .friendTypeChoice(let gameType):
            FriendTypeChoiceView(gameType: gameType)
        case .botDifficulty(let gameType):
            BotDifficultyView(gameType: gameType)
        case .lobby(let gameType):
            LobbyView(gameType: gameType)
        case .comingSoon(let gameName):
            ComingSoonView(gameName: gameName)
        case .account(let gameType, let premiumSource):
            AccountView(gameType: gameType, premiumSource: premiumSource)
        case .paymentWebView(let gameType, let premiumSource):
            // Real internet multiplayer is free and never reaches this
            // screen (see FriendTypeChoiceView) - every payment that lands
            // here is either a one-time single-game unlock or a subscription
            // purchase, both of which end the same way: straight into the
            // game the player originally wanted, same as onePhoneSelection
            // for free games.
            PaymentWebView(gameType: gameType, premiumSource: premiumSource) { selection in
                @MainActor func proceedToGame() {
                    router.replaceLobby(with: .onePhoneSelection(gameType: selection.gameType))
                }
                switch premiumSource {
                case "SUB_MONTHLY": SubscriptionManager.shared.markSubscribed("monthly") { proceedToGame() }
                case "SUB_YEARLY": SubscriptionManager.shared.markSubscribed("yearly") { proceedToGame() }
                case "EXPEDITION": SubscriptionManager.shared.markExpeditionUnlocked(gameType: selection.gameType) { proceedToGame() }
                default: proceedToGame()
                }
            }
        case .maxPlayers(let gameType):
            MaxPlayersView(gameType: gameType)
        case .onlineLobby(let gameType, let maxPlayers):
            OnlineLobbyView(gameType: gameType, maxPlayers: maxPlayers)
        case .hangmanModeChoice(let selection):
            HangmanModeChoiceView(selection: selection)
        case .instructionsChoice(let selection):
            InstructionsChoiceView(selection: selection)
        case .instructionsView(let selection):
            InstructionsScreenView(selection: selection)
        case .game(let selection):
            GameRouter.gameView(for: selection)
                .onAppear {
                    AppFeedbackService.incrementPlayCount(gameType: selection.gameType)
                    setLiveActivityContext(for: selection)
                }
                .onDisappear { LiveActivityManager.currentContext = nil }
        case .mathSprintSelection:
            MathSprintSelectionView()
        case .contactUs:
            ContactUsView()
        case .credits:
            CreditsView()
        case .dailyQuestion:
            DailyQuestionView()
        case .opponentDisconnected:
            OpponentDisconnectedView()
        case .login:
            LoginView()
        case .adminDashboard:
            AdminDashboardView()
        case .getUpdates:
            GetUpdatesView(onBack: { router.pop() })
        }
    }

    /// Feeds LiveActivityManager the "you vs them" context for the Dynamic
    /// Island shown if the player backgrounds mid-game - only ever set for a
    /// real multiplayer game (GameSelection.isNearby with a real player
    /// roster); anything else (local pass-and-play, vs bot, a solo game)
    /// clears it, since there's no real opponent name to show.
    private func setLiveActivityContext(for selection: GameSelection) {
        guard selection.isNearby,
              let players = selection.players, players.count >= 2,
              let myId = InternetConnectionManager.shared.myPlayerId(),
              let me = players.first(where: { $0.id == myId })
        else {
            LiveActivityManager.currentContext = nil
            return
        }
        let opponentNames = players.filter { $0.id != myId }.map { $0.name }.joined(separator: ", ")
        LiveActivityManager.currentContext = (gameType: selection.gameType, myName: me.name, opponentNames: opponentNames)
    }
}
