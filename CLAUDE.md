# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

BuddyVerse (iOS) is a native SwiftUI port of the Android BuddyVerse app (sibling project at `~/AndroidStudioProjects/BuddyVerse`) — the same ~27 mini-games (the goal is 30+) plus static "connect with friends" content (jokes/riddles/trivia/conversation starters, all built-in, no AI generation of any kind), with local pass-and-play, vs-bot, and real internet multiplayer modes, sharing the same Firebase project as the Android app. This project was scaffolded and the bulk of its games ported by Claude Code directly from the current Android Kotlin source, not written by hand first.

## Commands

```bash
xcodegen generate                          # regenerate BuddyVerse.xcodeproj from project.yml (source of truth — the .xcodeproj itself is gitignored)
xcodebuild -project BuddyVerse.xcodeproj -scheme BuddyVerse -destination 'generic/platform=iOS Simulator' build
open BuddyVerse.xcodeproj                  # open in Xcode for day-to-day iteration
```

**Simulators: only when the owner asks** (see "Simulators and emulators" below). This Xcode (27.1) has no standalone Simulator.app; it ships DeviceHub.app instead, and `xcrun simctl` still works. To check that a change compiles without signing, build for a generic device (no simulator needed):

```bash
xcodebuild -project BuddyVerse.xcodeproj -scheme BuddyVerse -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

After adding a new `.swift` file run `xcodegen generate` first, or the file is not in the project. `.claude/commands/test-app.md` runs the iOS QA agent team in `.claude/agents/` (static review plus that device build) and records results under Known Issues below.

`project.yml` is the source of truth for the Xcode project (target, dependencies, build settings) — edit it, not the generated `.xcodeproj`, and re-run `xcodegen generate` after.

**Deployment target is iOS 15.0** (`project.yml`'s `options.deploymentTarget.iOS` and `targets.BuddyVerse.deploymentTarget`; raised from 14.0 on 2026-10-29 because current Xcode no longer accepts 14.0, and the widget extension stays at 16.2). It was originally lowered from 17.0 so the app runs on older/hardware-capped devices (e.g. iPads stuck on iOS 15.x that can't upgrade further). The code still follows the iOS 14 rules below; keeping them is harmless, and only the iOS 15 items in that list could now be relaxed. This has real, easy-to-reintroduce consequences for anyone touching this codebase — see "iOS 14 compatibility constraints" below before writing new SwiftUI code here.

**App Store setup (2026-10-29):** bundle IDs are `com.obliprabu.buddyverse` (matching Android's applicationId), `com.obliprabu.buddyverse.BuddyVerseWidget` and `com.obliprabu.buddyverse.UITests`; Apple's bundle ID can't change after the first submission. `BuddyVerse/Resources/PrivacyInfo.xcprivacy` declares the UserDefaults (CA92.1) and System Boot Time (35F9.1, the Chess bot's time limit via `ProcessInfo.systemUptime`) required-reason APIs, no tracking, and the data sent to Firestore (first name, admin-login email, anonymous multiplayer id, feedback/report text, play counts; matches App-Privacy-Answers.txt); update it if the app starts using another required-reason API or collecting more. `ITSAppUsesNonExemptEncryption` is `false` (HTTPS only).

**Daily pick holidays (2026-10-31):** `DailyContentPool.holidayRiddles`/`holidayPick` replace the daily pick with a holiday riddle on New Year's Day, Valentine's Day, St. Patrick's Day, Earth Day, July 4, Halloween, Christmas Eve/Day, New Year's Eve and Thanksgiving (4th Thursday of November); Android's `DailyContentPool.kt` has the identical list. **Mac build:** the app target has `SUPPORTS_MACCATALYST` (widget iOS-only, Live Activity stubbed in `LiveActivityManager.swift`); the unsigned `.dmg` is attached to the GitHub release `v1.6.25-mac`.

### One-time setup this project can't do for itself

- **`BuddyVerse/Resources/GoogleService-Info.plist`** — gitignored, and **currently present** on this machine (bundle ID `com.obliprabu.buddyverse`, registered as its own iOS app on 2026-10-29 when the bundle ID changed from `com.example.buddyverse.ios`; same Firebase project as the Android app, `buddyverse-5fc3e`). On a fresh checkout it has to be re-downloaded from the Firebase console and dropped in this exact path. Without it, `FirebaseApp.configure()` is skipped (guarded in `BuddyVerseApp.swift`) and every multiplayer screen will fail to connect — everything else in the app works fine without it.

## Git workflow

_Standing instruction from the owner (2026-11-05): commit and push automatically. Do not ask first._

- **Commit and push on your own.** After finishing a change that builds and whose tests pass, commit it and push it to the branch you are on - including `main` when that is where you are working. Do this at natural stopping points, not after every tiny edit, and do not stop to ask for permission.
- **If a push is rejected** because GitHub has newer commits (for example a robot or a cloud session pushed), run `git pull --rebase` to put your commits on top of theirs, run the build/tests again if the incoming changes touch code you changed, then push again. If the rebase has conflicts you cannot resolve safely, stop and tell the owner.
- **Never force-push** and never rewrite history that is already pushed.
- **Never commit secrets or local files:** `local.properties`, `*.jks` / `*.keystore`, `GoogleService-Info.plist`, API keys, provisioning files, and `.idea/` changes (unless asked). Stage the project's own files by name instead of `git add -A`.
- **Cloud-session branches** (`claude/...`): fetching is fine, but merging one into your work still happens only when the owner says to pull.
- **Write real commit messages:** a short summary line, then what changed and why in plain English, ending with the usual `Co-Authored-By` line.
- **Pushing is not releasing or installing.** Uploading to Google Play, publishing a Mac `.dmg`, editing the website, and installing on the owner's own devices still happen only when asked. Never install on Arjun Prabu's iPhone.

## Simulators and emulators

_Standing instruction from the owner (2026-11-05): do not use them unless asked._

- **Never start, boot, install on, or drive an emulator or simulator (Android emulators, the iPhone Duo or any other iOS simulator) unless the owner asks for it in that message.** This includes "just to test a change": build and run the unit tests instead, and ask the owner if a screen needs to be seen.
- If the owner does ask, tell them what you are starting, and shut it down again (and uninstall any test-runner apps you added) when the task is done.
- Real devices are separate: install on the owner's own phone only when asked (see the Git workflow section's last bullet).

## Architecture

Mirrors the Android app's architecture almost 1:1 — see `~/AndroidStudioProjects/BuddyVerse/CLAUDE.md` for the full narrative description of the product/flow; this file only covers what's iOS-specific.

### Navigation

Android chains `AppCompatActivity` screens via `Intent` + extras, with (almost) every screen calling `startActivity()+finish()` so its real back stack stays shallow. This port uses `App/RootView.swift`'s `Router` (`@Published var path: [AppRoute]`) with normal push/pop semantics instead — a deliberate departure, not a literal port: iOS users expect the back button to return to the *immediately previous* screen, not always to Welcome. `Router.replaceTop(with:)` swaps the top entry instead of pushing, so a screen the player must not return to leaves nothing behind. It is used for the purely automatic `AiGeneratingView`, and on purpose for the online hand-off (lobby -> mode choice / instructions) and for "NO, I KNOW THE RULES" / the instructions start button, which match Android's `finish()`: Back from the game goes to the screen before them. `Router.replaceLobby(with:)` removes the premium Lobby entry and everything above it (Account, payment) - use it for a purchase or entitlement hand-off so Back never lands on the paywall again.

**`RootView` renders `path` itself in a plain `ZStack`, not a real `NavigationStack`** — `NavigationStack`/`.navigationDestination(for:)` both need iOS 16+, and this app's floor is iOS 14. Every entry in `router.path` stays mounted (indices are stable, since push only appends and pop only drops the last one) so a screen's `@State` survives the player backing into it, and a `.move(edge:)` transition + `.animation()` gives the same push/pop slide `NavigationStack` gives for free. There's deliberately no interactive edge-swipe-to-back gesture (a hand-rolled one risks fighting screens with their own drag gestures, like `WordSearchView`'s selection drag) — every screen already renders its own visible "Back" button calling `router.pop()`, which is the only way back navigation happens here. Don't reach for `NavigationStack`/`.navigationDestination`/`@Environment(\.dismiss)` on a new screen out of habit — use `@EnvironmentObject private var router: Router` and `router.pop()` instead, matching every existing screen.

`AppRoute` (in `App/AppRoute.swift`) enumerates every screen; `GameSelection` is the Swift equivalent of Android's bag of Intent extras (`GAME_TYPE`/`DIFFICULTY`/`IS_BOT`/`IS_NEARBY`/`MOOD`/`AGE_GROUP`/`WORD_MODE`/`PLAYERS`; there is no `AI_ITEMS` anymore, the AI path was removed), passed by value along the navigation path. `GameRouter.gameView(for:)` is the direct equivalent of `InstructionsChoiceActivity.createGameIntent()` — the one place that maps a `GAME_TYPE` string to its game view; add a new game there.

### Expedition framework games (2026-11)

Mirrors Android's `ArcadeCore.kt`/`ExpeditionActivity.kt`. A game is a plain-Swift class extending `ArcadeBase` in `Games/Expedition/<Name>Game.swift` (Foundation only, so it is unit-testable without SwiftUI): `goal`/`score`/`lives`/`status`/`hud`/`controls`, `step(dtMs:)`, `sprites()` of emoji `ArcadeSprite`s (0...1 of the square play area), `onControl(id:pressed:)` and `onTapArena(x:y:)`. The names that could clash with SwiftUI carry an `Arcade` prefix here (`ArcadeSprite`, `ArcadeControl`, `ArcadeGrid`); Android uses the bare names. `ExpeditionView` (config + a `makeGame` closure, routed from `AppRoute.gameView`) is the one screen they all share: 30 fps loop, hearts, a best per difficulty in UserDefaults (`<id>_best_<difficulty>`), win/lose overlay with confetti, Back/Home/Feedback/Report, and pausing when the app resigns active or a Feedback/Report sheet is open. `GameRng` is a seedable SplitMix64 for deterministic tests. To add a game: write `XGame.swift`, then register it in `GameCatalog.swift` (`soloGamesWithNoBot`), `AppRoute.gameView`, `InstructionsScreenView`, `AppFeedbackService`, `WelcomeView.premiumGames` and the "Original games" counter (now 27), and the same on Android. The `BuddyVerseTests` target compiles the whole `Games/Expedition` folder except `ExpeditionView.swift`. Because those tests need a simulator to run in Xcode, they can also be run natively on a Mac with a throwaway Swift package containing those files plus `BuddyVerseTests/Expedition*Tests.swift` (`swift test`). Canyon Zipline and Meteor Shower used to be "Coming Soon" placeholders; `ComingSoonView` is now orphaned.

- **Canyon Zipline** (`ZIPLINE`, `ZiplineGame`): three ziplines; coins and eagles slide down; tap left/right (or either half of the play area) to swap lines; 15 coins to win, an eagle costs a heart.
- **Meteor Shower** (`METEOR`, `MeteorGame`): hold the ◀ ▶ buttons to steer a rocket along the bottom (a tap on the sky nudges it); catch 12 stars, a meteor costs a heart.
- **Dino Valley** (`DINO`, `DinoValleyGame`): turn-based walk on a 5x5 valley (arrow buttons or tap a neighbouring square); collect 5 eggs; after every step the friendly dinosaurs (2, or 3 on HARD) wander one step and a bump sends you back to the start and costs a heart.
- **Pirate Island** (`PIRATE`, `PirateIslandGame`): dig on a 5x5 island; each dig shows how many traps touch that square and a sparkle if the chest is next to it; a trap costs a heart; points = 100 + 20 per heart left - 3 per dig (min 10).

### iOS 14 compatibility constraints

This app's SwiftUI code was originally written assuming a modern (17.0) deployment target, then had to be systematically walked back to 14.0 — that pass touched ~50 files, since APIs that feel like basic, everyday SwiftUI (`.foregroundStyle()`, `.tint()`, `.buttonStyle(.borderedProminent)`/`.bordered`, `Canvas`, `@FocusState`, `.confirmationDialog`, `TextField(prompt:)`, `.onChange(of:)`'s newer closure forms, `.task {}`, `.overlay(alignment:) {}`, `.alert(_:isPresented:presenting:actions:message:)`, `Button(_:role:action:)`, `.scrollContentBackground`) all turned out to require iOS 15, 16, or 17. When adding new SwiftUI code to this project, default to the *older* form of anything that has one, and verify with an actual `xcodebuild ... build` (not just "it looks right") before considering a change done, since some of these fail silently in an editor but hard-error at the deployment target check:

- **Text/shape color**: `.foregroundColor()`, not `.foregroundStyle()`.
- **Tinting**: `.accentColor()`, not `.tint()`.
- **Filled/bordered buttons**: `LegacyProminentButtonStyle(tint:)`/`LegacyBorderedButtonStyle(tint:)` (`Core/LegacyButtonStyles.swift`), not `.buttonStyle(.borderedProminent)`/`.buttonStyle(.bordered)` + `.tint()`. Neither custom style sets its own foreground color (matching the real APIs' behavior) — chain `.foregroundColor()`/`.foregroundStyle()` after `.buttonStyle()` for anything other than `LegacyProminentButtonStyle`'s implicit "whatever the label already has" default, and add an explicit `.foregroundColor(.white)` if you want the real `.borderedProminent` default look.
- **Custom drawing**: build a `Path` and `.stroke()`/`.fill()` it directly (`Path` has conformed to `Shape` since iOS 13) inside a `GeometryReader`, not `Canvas { context, size in ... }` — see `HangmanFigureView`/`MazeGameView.mazeCanvas` for the pattern, including how to hand-bake a coordinate offset that `Canvas`'s `context.translateBy` would have done for you.
- **Keyboard focus** (`@FocusState`): a stored property of an iOS-15+-only type can't be conditionally present on one struct depending on OS version (unlike a modifier call, which *can* be wrapped in `if #available`) — pull it into its own small `@available(iOS 15, *)`-gated helper view instead, and call that from an `if #available(iOS 15, *) { ... } else { plainVersion }` branch. See `AutoFocusingAnswerField` (`MathSprintView.swift`) and `KeyboardControlledMazeCanvas` (`MazeGameView.swift`, also gated to iOS 17 for `.onKeyPress`).
- **Alerts**: `.alert(isPresented:) { Alert(title:message:dismissButton:) }` (one button) or `Alert(title:message:primaryButton:secondaryButton:)` (two), not the `actions:`/`message:` closure overload — and no `role:` on the dismiss button (`Button(_:role:action:)` is iOS 15+ too).
- **Action sheets**: `.actionSheet(isPresented:) { ActionSheet(title:buttons:) }`, not `.confirmationDialog`.
- **Text field placeholder styling**: build it by hand (`ZStack` layering a conditional `Text` placeholder under the real field, shown only while empty — see `AccountView.placeholderField`), not `TextField(_:text:prompt:)`.
- **Kicking off async work on appear**: `.onAppear { Task { ... } }`, not `.task {}`.
- **Positioned overlays**: `.overlay(someView, alignment: .topLeading)`, not the labeled-alignment trailing-closure `.overlay(alignment:) { ... }`.
- **`.onChange(of:)`**: only the single-parameter `{ newValue in ... }` closure form works; both the zero-parameter and `{ oldValue, newValue in }` forms need iOS 17.
- **`.background(_:)` ambiguity**: a bare `.background(.white)` (or any dot-shorthand `ShapeStyle` literal) can silently resolve to the iOS-15+ `background(_:ignoresSafeAreaEdges:)` overload instead of the iOS-13+ View-based one — spell it out as `.background(Color.white)`. `.background(_:in:)` (a shape + fill in one call) is iOS 15+ outright; use `.background(RoundedRectangle(cornerRadius:).fill(Color.x))` instead.
- `TextEditor` has no pre-iOS-16 way to hide its background via `.scrollContentBackground(.hidden)` — the `UITextView.appearance().backgroundColor = .clear` proxy trick is used instead (`ConversationView.swift`); safe only because it's the app's one and only `TextEditor`.

### Cross-cutting singletons (`Core/`)

- `InternetConnectionManager` — a from-scratch Swift port of the Android object of the same name, using `FirebaseFirestore`/`FirebaseAuth` directly (closure-based API, not async/await, to stay a close structural match to the Kotlin callback style). Same room-code/anonymous-auth/transactional-join/message-buffering/word-mode-sync design as Android; keep the two in sync if the wire protocol changes on either side, since they talk to the same Firestore project. It now also mirrors Android's later hardening (see Android `CLAUDE.md` ISSUE-26/34/55/60/69/78/85/90/91/94/106/115/116/117/120/121): a transactional room-code create, a 6-digit ASCII code check plus a 3-minute host-`lastSeen` TTL on join, a `startGame()` transaction that freezes `startedPlayers` (read back through `playersForGame()`), a 10s `lastSeen.<id>` heartbeat with the same 90s peer-stale / 45s own-ack / 25s late-tick constants, a guest-left-mid-game and listener-error / failed-send / vanished-room path into `onDisconnected`, sender-aware delivery (`setListeners(... onMessageWithSender:)`, exactly one of the two callbacks fires), `setInterstitialDisconnectListener`, and chunked (400) host cleanup. Two iOS-specific differences: the 60s background grace is judged when the app returns to the foreground (iOS suspends the process, so no timer can run while away), and every Firestore callback that touches UI hops to the main thread through `runOnMain` (`Core/MainActorHelpers.swift`). Games that verify senders (Count to 21, Memory, Hangman, Arctic/Cave/Desert) pass `onMessageWithSender`; Tic-Tac-Toe checks role and turn locally. Not tested on devices.
- `ThemeManager` / `MusicManager` / `ConfettiView` (`ConfettiController` + `.confettiOverlay(_:)`) — direct analogues of `ThemePrefs`/`MusicManager`/`ConfettiView.kt`.
- `StripeConfig` / `PendingPayment` / `PaymentWebView` (in `Navigation/`) — port of the real Stripe Payment Link checkout flow (`LobbyActivity` → `PaymentWebViewActivity`), embedded in a `WKWebView` (`TrustedWebView`) the same way Android embeds it, watching navigation for `StripeConfig.paymentSuccessHost` as the success signal.
- `AuthManager` — thin wrapper around Firebase email/password auth (a real, recoverable account, distinct from `InternetConnectionManager`'s anonymous multiplayer auth). `AuthManager.isAdmin()` checks the signed-in account's email against one hardcoded admin address; it's the only gate on `AdminDashboardView` and on whether the "🎉 Creator" pill's sibling "Admin Login"/"🛠️ Admin Dashboard" footer links on `WelcomeView` do anything visible. Sign in via `LoginView` (`router.push(.login)`).
- `AppFeedbackService` — every piece of self-reported, no-backend Firestore data the app writes or reads outside of gameplay itself: play counts (`incrementPlayCount`, called once per game launch from `RootView`'s `.game` case), free-text `submitFeedback`/`submitReport`, the mandatory name-gate's `submitAppUser`, the optional `submitUpdateOptIn`, and the update-banner pair `checkForUpdate`/`autoPublishUpdateIfNewer` (see below). All admin-only reads are gated the same way as `AuthManager.isAdmin()` at the Firestore security-rules level, not just in the client.

### Per-game pattern

Each game is `BuddyVerse/Games/<Name>/<Name>View.swift`, a SwiftUI `View` taking `selection: GameSelection` (except `MathSprintView`, which takes `roundSeconds: Int` directly, matching how Math Sprint bypasses the `GAME_TYPE` routing hub on Android too). No shared base view or protocol — matches Android's "no shared base class" convention. Bot AI, wire protocols, and generators (Sudoku, Maze) are ported per-game, not shared.

**Known deliberate deviation from Android**: the 5 tug-of-war expedition games (Arctic/Cave/Desert/Mountain/Volcano Trek/Climb/Explorer) had a confirmed bug on Android where local pass-and-play softlocks after the first tap (the button only re-enables via a scheduled bot move, so with no bot there's nothing to hand the turn back). The iOS port fixes this rather than reproducing it — both local players can act on alternating turns.

**Known platform divergence (not yet ported)**: Android's premium-expedition paywall (`LobbyActivity`) is currently switched off — every premium game there goes straight from `WelcomeActivity` to the game itself, free, for a limited promotional period (see `WelcomeActivity.startPremiumFlow`'s own doc comment). iOS was never updated to match: `WelcomeView`'s premium buttons still push `.lobby(gameType:)`, and `LobbyView` still checks `SubscriptionManager.shared.isSubscribed`/`isExpeditionUnlocked` and can route into the real Stripe checkout (`PaymentWebView`). Don't assume the two platforms currently behave the same for premium games — check which promotional state is live on each before touching this flow.

### Chess

`Games/Chess/` is a port of Android's Chess: `ChessEngine.swift` (`ChessRules`, `ChessBot`, written from scratch, no chess library), `ChessOnline.swift` (`ChessWire`, the online message format) and `ChessView.swift` (the SwiftUI board and game screen: vs bot, one phone, or two phones). Square numbering (0 = a8 ... 63 = h1) and the wire format are **byte-for-byte the same as Android's** `ChessEngine.kt`/`ChessOnline.kt` so mixed iOS/Android rooms work; change both together. Chess is in `GameCatalog.realMultiplayerGames` but not `multiSeatMultiplayerGames` (strictly 2 players, auto-start like Tic-Tac-Toe). Messages are `<round>:MOVE:<from>:<to>:<promo>`, `<round>:RESIGN` and `<round>:RESET` (round + 1); there is no HELLO handshake, the room's player order decides colours: seat 0 (host) plays White in round 0 and colours swap each round (`whiteSeat(round) = round % 2`). Messages arrive through `onMessageWithSender`; a MOVE is applied only if the sender is the seat to move and the move equals one of `ChessRules.legalMoves`, anything else is dropped. Black sees the board flipped. A promotion sheet left open is ignored if the game or round changed meanwhile (Android ISSUE-197). **Status:** written without a Swift compiler and not yet built or run; there is no unit-test target on iOS, so Android's `ChessEngineTest` (perft counts) and `ChessWireTest` have no iOS equivalent yet. Build with `xcodegen generate` first (new files), then `xcodebuild`, and play a game against the bot and a two-phone room before trusting it.

The Android QA fixes ISSUE-202/203/204 (daily-pool wording, Netherlands trivia option, shadow riddle) were mirrored here in `DailyContentPool.swift`, `TriviaView.swift` and `RiddlesView.swift`. Android ISSUE-198/199/200 (lobby grace-stop when a start is held in the background, Tic-Tac-Toe repeated-HELLO guard, strict 6-digit join code) are Android-only changes: the iOS 6-digit check is already strict, but the other two have not been checked against the iOS code.

Unit tests live in the `BuddyVerseTests` target (`BuddyVerseTests/ChessEngineTests.swift`, `SudokuGeneratorTests.swift`; it compiles `ChessEngine.swift` and `SudokuGenerator.swift` directly, no app launch needed). Run them with `xcodebuild -project BuddyVerse.xcodeproj -scheme BuddyVerse -destination 'platform=iOS Simulator,id=<udid>' -only-testing:BuddyVerseTests test`. The engine here also has the repetition-key, FEN-parsing and insufficient-material fixes (2026-11-04); keep it in step with Android's `ChessEngine.kt`.

**Online extras (2026-11-05), mirroring Android's `ChessActivity.kt`.** `OnlineLobbyView` pins Cancel to the bottom and shows a clock choice (None / 3 / 5 / 10 min) for chess only; the host's choice reaches `ChessView` through `ChessSettings.hostClockSeconds` and the guest through a `<round>:CLOCK:<seconds>` message. `ChessClock` (in `ChessOnline.swift`) takes "now" as a parameter so `BuddyVerseTests/ChessWireTests.swift` can test it. Timeouts, draw offers (`DRAW`/`DRAWOK`/`DRAWNO`), takebacks (`TAKEBACK:<ply>`/`TBOK`/`TBNO`) and agreed new games (`NEWGAME`/`NEWNO`; `RESET` is ignored unless the game is over or we proposed it) follow the rules written up in Android's CLAUDE.md Chess section - change both platforms together. All dialogs share one `ChessAlert` enum because SwiftUI shows one alert per view; a proposal that arrives while another dialog is open is declined automatically. A friend's move buzzes and toasts when the app is active, otherwise `LocalNotificationManager.notifyChessMove` posts a local notification (an iPhone app is suspended soon after leaving, so this only works for a short time; there is no push service). The rank numbers (down the right side) and file letters (along the bottom) sit in strips beside the board. **Timed bot and one-phone games (2026-11-05):** the clock is no longer online-only. Before the first move of a vs-bot or one-phone game a "Clock:" row offers None / 3 / 5 / 10 min (`clockSeconds`, kept across New Game); the clocks then show "You"/"Bot" (vs bot, you are White) or "White"/"Black" (one phone), and whoever's clock reaches zero on their turn loses on time (`checkLocalTimeout`) - there is no TIMEOUT message because there is no other phone. A bot move that finishes thinking after the clock ended the game is discarded. Online games still take their clock from the host's lobby choice.

### Mandatory first-launch gate, Get Updates, and Admin Dashboard

Both ported from Android features added after this file's initial architecture pass — see `AppFeedbackService`'s doc comments (above) for the Firestore side of all of these.

- **`EnterNameView`/`GetUpdatesView`** (`Navigation/`) — a mandatory, first-launch-only "what's your first name?" gate followed by an optional "get updates" opt-in. Deliberately first-name-only, never an email or full name (not regulated "personal information" under COPPA the way a full name/email is), since this app's Kid content mode means it can genuinely be used by children — see `AppFeedbackService.submitAppUser`/`submitUpdateOptIn`'s doc comments for the fuller reasoning.
- **`RootView`'s gate overlay** — rather than a pushed `AppRoute` (which would need somewhere to pop back *to*), the gate is a plain `ZStack` layer drawn on top of the router's normal content, toggled by a `hasEnteredName` `@State` seeded from `UserDefaults`. This mirrors Android's approach (`EnterNameActivity` started on top of an already-`onCreate()`'d `WelcomeActivity`, never finishing it) using SwiftUI's own idioms instead: `WelcomeView` and the router's content stay mounted underneath the whole time, so finishing the gate just flips a boolean and reveals them — no relaunch, no separate route to manage.
- **Update banner** — `WelcomeView` calls `AppFeedbackService.checkForUpdate` on appear (only if this device opted into Get Updates), which reads the single global `appConfig/latest` Firestore doc and shows a dismissable yellow banner if it names a version *genuinely newer* (a real dotted-version-number comparison, not a `!=` check) than `CFBundleShortVersionString`. `autoPublishUpdateIfNewer` is the write side: called whenever `AuthManager.isAdmin()` is true and `WelcomeView` appears (or the router path empties back out to it), it publishes the currently-running build's own version to that same doc if newer than what's already there — so the version number auto-publishes itself the moment the admin opens a freshly-installed build, without ever needing to hand-type it into the Admin Dashboard. The two must use the *same* "newer than" comparison, or the admin's own device can flash a nonsensical "downgrade" banner in the instant before its own auto-publish write lands.
- **`AdminDashboardView`** — reachable only via the "🛠️ Admin Dashboard" footer link on `WelcomeView`, itself only visible when `AuthManager.isAdmin()` (checked on appear and whenever the router path empties back to Welcome, so logging in/out is reflected without a relaunch). Shows play counts, feedback, reports, the Updates publish form (version/message fields + subscriber list) and app-user (name-gate) records, all mirroring Android's sections — deliberately **no revenue/purchase log** on iOS to match Android's dropped section (see the platform-divergence note above: Android's paywall being off made that section meaningless there; it was removed on both platforms for parity even though iOS's own paywall is still technically live). Deletion exists only for feedback/report rows, each behind a confirmation `Alert` — Play Counts, app users, and Get Updates subscribers are intentionally read-only (matches Android exactly; a delete-with-confirmation pass was added to all three and then explicitly reverted per product decision, keep it that way unless told otherwise). **History note:** the Updates form and App Users list were first ported to `AppFeedbackService` only, with no actual UI in `AdminDashboardView` for a while — don't assume a function existing in `AppFeedbackService` means its screen was ever built; check the view file too.

### Known platform gaps

- **No background music on iOS.** `MusicManager` looks for `background_music.{mp3,m4a,wav,aac}` in the bundle and silently does nothing if there isn't one; `BuddyVerse/Resources/` contains none, so the app is silent. Dropping a file there is enough (no code change).
- **Difficulty screen is orphaned.** Every Connect game (jokes/riddles/trivia/conversation) now goes mood -> age group with a placeholder difficulty, same as Android; `DifficultySelectionView` and its route are still compiled but nothing navigates to them.
- **Simpler expedition games.** Ocean Dive, Savanna Safari, Mountain Climb, Storm Chase and Swamp Trek are the older single-loop versions without Android's zones, goal, streak multiplier or personal best, and Ocean Dive/Savanna have no win state.

### Conventions

Comments follow the Android project's established style: plain-English explanations of *why*, not terse dev-shorthand — match this when touching existing files.

### Home-screen widget and Question of the Day
`BuddyVerseWidget/DailyContentWidget.swift` shows a joke, riddle or trivia question of the day from `Core/DailyContentPool.swift` (shared with the widget target) - kind = `dayOfYear % 3`, entry = `(dayOfYear / 3) % 30`, identical to Android's `DailyContentPool.kt` (same entries, same order; keep them in sync). Tapping it sends `buddyverse://daily/question`; `DeepLinkManager` stashes `.dailyQuestion` and `RootView.consumePendingDeepLink()` replaces the stack with it (ending any live room first, and waiting for the name gate). `DailyQuestionView` has the "Go to Jokes/Riddles/Trivia" button.

## Known Issues

_Maintained by `/test-app` (adds findings from the iOS QA agent team in `.claude/agents/`) and fixed by hand or by a fixer pass. Entries are numbered sequentially and never reused or renumbered. Findings marked 'Android ISSUE-N' are fixes already made on Android that were never ported._

### Open

#### ISSUE-11: Unused Gemini API key left on disk
- **Severity:** LOW
- **Area:** content
- **File:** BuddyVerse/Resources/Secrets.plist:5
- **Found by:** qa-content (2026-10-15)
- **Description:** Not bundled, not committed, not referenced by code, but a live-looking secret sits in the project tree.
- **Suggested fix:** Delete the file and revoke the key (key revocation is the owner's to do).
- **Status (2026-10-17):** Local file deleted at the owner's request, and `project.yml` now excludes `Resources/Secrets.plist` from the target (xcodegen had been copying it into the app bundle, so builds up to 1.6.10 (54) may have shipped the key). **Still open for the owner:** revoke the key in the Google console, since it is in any previously built IPA and in this session's logs.
- **Earlier status (2026-10-15):** Left for the owner. The file is not referenced by any code, not bundled and not committed, but it holds a live-looking key. Only the owner can revoke the key in the Google console; deleting the local file is also left to the owner because it cannot be undone.

#### ISSUE-12: Admin dashboard shows a leftover 'TEST' pill and has a stale comment
- **Severity:** LOW
- **Area:** content
- **File:** Navigation/AdminDashboardView.swift:379-386, 25-26
- **Found by:** qa-content (2026-10-15)
- **Description:** testBuildMarker is a debug leftover; a comment says play counts have delete actions but they are read-only.
- **Suggested fix:** Remove the marker and fix the comment.
- **Status (2026-10-15):** **Partly fixed.** The stale comment was corrected. The 'TEST' pill was left in place on purpose: its own comment says it is a deliberate marker for confirming a fresh build is running, so removing it is the owner's call.

#### ISSUE-52: Simplified games lack Android's zones/goal/streak/personal best (parity note)
- **Severity:** LOW
- **Area:** game-logic
- **File:** Games/OceanDive, SavannaSafari, MountainClimb, StormChase, SwampTrek
- **Found by:** qa-game-logic (2026-10-15, second /test-app pass)
- **Description:** Older single-loop versions; Android ISSUE-72/73/98 balance fixes do not apply. Ocean Dive and Savanna have no win state.
- **Suggested fix:** Owner decision; feature gap, not a crash.
- **Status (2026-10-15):** **Left for the owner.** A feature-parity gap (porting zones/goal/streak/personal best to five games), not a bug; documented under Known platform gaps. Needs a product decision and device playtesting.

#### ISSUE-72: Hangman PICKER tie and no `lastSeen` write at join (parity notes)
- **Severity:** LOW
- **Area:** multiplayer
- **File:** Games/Hangman/HangmanView.swift, Core/InternetConnectionManager.swift
- **Found by:** qa-multiplayer (2026-10-15, third /test-app pass)
- **Description:** Two PICKER guessers ending the round in the same instant can show different outcomes locally (nothing hangs); a guest that dies within ~10 s of joining never writes `lastSeen`, so the host never judges its seat stale.
- **Suggested fix:** Tie-break by lowest seat; write `lastSeen.<guestId>` in the join transaction (needs the live Firestore rules to allow it).
- **Status (2026-10-15):** **Left open on purpose** - the tie is cosmetic and the join-write change touches the live protocol against rules this repo cannot see. Same as Android ISSUE-140.

#### ISSUE-90: Turning off updates leaves the updatesOptIn doc
- **Severity:** LOW
- **Area:** content
- **Found by:** qa-content / qa-game-logic (2026-10-17)
- **Description:** Opt-out only clears the local flag; the Firestore doc cannot be removed without a device link and a rules change (also duplicates on re-opt-in).
- **Status (2026-10-17):** Deferred on purpose.

#### ISSUE-91: Sudoku HARD generation may be slow on some seeds (unverified)
- **Severity:** LOW
- **Area:** content
- **Found by:** qa-content / qa-game-logic (2026-10-17)
- **Description:** countSolutions has no most-constrained-cell ordering.
- **Status (2026-10-17):** Deferred on purpose.

#### ISSUE-97: Back from an online game can land on a dead Ready-to-Play screen
- **Severity:** LOW
- **Area:** navigation
- **Found by:** /test-app sixth pass (2026-10-17)
- **Description:** InstructionsChoiceView stays in the stack under the game; Back after stop() shows it with no room behind it.
- **Status (2026-10-17):** Deferred on purpose.
- **Status (2026-11-05):** Broader than recorded. "YES, SHOW ME HOW" pushes `.instructionsView` over `.instructionsChoice` and START GAME only `replaceTop`s the instructions screen, so Back from ANY game (bot, pass-and-play, solo, online) lands on the already-answered "Ready to Play?" prompt (InstructionsScreenView.swift:82, InstructionsChoiceView.swift:49-50). Android's choice screen finishes itself, so Back skips the prompt. For online games the prompt is also dead (its room was stopped), and tapping "NO, I KNOW THE RULES" there re-launches a nearby game that immediately shows "Opponent Disconnected". Suggested fix: on START GAME drop both entries (`pop()` then `replaceTop`, or a helper that removes two), and optionally pop `InstructionsChoiceView` automatically when `selection.isNearby && !InternetConnectionManager.shared.isConnected()`.

#### ISSUE-98: Memory Match and Count to 21 have no idle-player skip (Android ISSUE-142 style)
- **Severity:** MEDIUM
- **Area:** multiplayer
- **Found by:** /test-app sixth pass (2026-10-17)
- **Description:** Only the Treks and Hangman offer SKIP; a connected-but-idle player stalls these games (Android finding; same protocol on iOS).
- **Status (2026-10-17):** Deferred on purpose.

#### ISSUE-102: iOS-only 300 s lobby tolerance breaks mixed iOS/Android lobbies
- **Severity:** MEDIUM
- **Area:** multiplayer
- **File:** Core/InternetConnectionManager.swift:690 and :757-789 (Android InternetConnectionManager.kt:730, :805-819)
- **Found by:** qa-multiplayer / parity audit (2026-10-28)
- **Description:** An iOS host backgrounded in the lobby for over 90 s stops its `lastSeen`; an Android guest then drops the room with "game ended", while an iOS guest would wait 300 s. An iOS guest backgrounded over 90 s is quietly removed by an Android host and hits the `evicted` path on return. The code comment says the constants match Android "on purpose", which this one doesn't. Same item as Android ISSUE-170.
- **Suggested fix:** Match the tolerance on Android, or keep the iOS host's `lastSeen` fresh while the lobby shows (ISSUE-101's fix covers most of it).
- **Last attempt:** 2026-10-28 — Android now lets a guest wait 300 s on a silent lobby host (Android ISSUE-170), which closes the iOS-host-backgrounded case; ISSUE-101 keeps the screen awake while a room is live. Still open: an Android host evicts a stale guest after 90 s, so a backgrounded iOS lobby guest can still be removed.
- **Status (2026-11-05):** The 90 s eviction itself is unchanged; the misleading "game ended" message shown to an evicted lobby guest is tracked separately as ISSUE-133.

#### ISSUE-107: Hangman mode choice: the guest waits forever and the host's mode write can fail silently
- **Severity:** LOW
- **Area:** multiplayer
- **File:** Navigation/HangmanModeChoiceView.swift:72-78; Core/InternetConnectionManager.swift:631-634
- **Found by:** qa-multiplayer (2026-10-28)
- **Description:** Android ISSUE-116 gave the guest's "Waiting for your friend to choose..." a 3-minute timeout; iOS has none. `chooseWordMode` calls `updateData` with no completion handler and the host moves on at once, so a failed write leaves the host in the game and the guest waiting indefinitely.
- **Suggested fix:** Add a 3-minute guest timer that stops the session and shows the friend-left screen; check the `updateData` error and route it through `handleConnectionLost`.

#### ISSUE-108: Trek late-TURN allowance can be cleared by another player's TURN, desyncing the shared pool
- **Severity:** LOW
- **Area:** multiplayer
- **File:** Games/ArcticTrek/ArcticTrekView.swift:332-363 (same in Cave and Desert); Android ArcticTrekActivity.kt:229-232
- **Found by:** qa-multiplayer (2026-10-28)
- **Description:** If skipped player X's TURN reaches the server after the next player C's, C's TURN clears `lastSkippedId` on the other phones, X's TURN is dropped, and X's phone keeps X's numbers while the others don't. Related to Android ISSUE-164 (the 2-player turn-split variant).
- **Suggested fix:** Clear `lastSkippedId` only on the skipped player's own TURN or when the turn wraps back to them, or add a turn counter to TURN/SKIP; change both platforms together.

#### ISSUE-109: Jungle Run and Mountain Climb keep applying penalties while the Feedback/Report sheet is open
- **Severity:** LOW
- **Area:** game-logic
- **File:** Games/JungleRun/JungleRunView.swift:151-153 and :231-236; Games/MountainClimb/MountainClimbView.swift:155 and :299-310
- **Found by:** qa-game-logic (2026-10-28)
- **Description:** They pause only on `scenePhase != .active` or disappear, and presenting a `.sheet` does neither. Jungle's fruit timeout keeps costing stamina and can reset the score to the zone floor; Mountain's armed gust can cost grip.
- **Suggested fix:** Pause when `showFeedback`/`showReport` becomes true and resume when it clears.

#### ISSUE-110: Mountain Climb: the tap that loses the last grip still arms a wind gust
- **Severity:** LOW
- **Area:** game-logic
- **File:** Games/MountainClimb/MountainClimbView.swift:258-265 with :280-290
- **Found by:** qa-game-logic (2026-10-28)
- **Description:** After `loseGrip` resets height, grip and `hasTapped`, `onStepTapped` still runs `scheduleWindGust()`, so a gust takes a grip from a player who hasn't restarted climbing.
- **Suggested fix:** Return early after a grip-reset `loseGrip`, or skip `scheduleWindGust()` while `hasTapped` is false.

#### ISSUE-111: Four Swift concurrency (Sendable) warnings that become errors in Swift 6 mode
- **Severity:** LOW
- **Area:** build
- **File:** App/RootView.swift:95; Core/AdminFeedbackChecker.swift:19 and :24; Core/LocalNotificationManager.swift:25
- **Found by:** qa-build-lint (2026-10-28)
- **Description:** The device build succeeds. Warnings: `storeUpdate` mutated from a Sendable closure (RootView:95, surfaced after `UpdateChecker.check`'s completion was marked `@Sendable` on 2026-10-27); captured `var feedbackDocs`/`reportDocs` mutated from Firestore callbacks; captured `var parts` read in the `requestAuthorization` closure. `xcodegen` isn't installed on this machine, so the existing `.xcodeproj` was built without regenerating from `project.yml`.
- **Suggested fix:** Set `storeUpdate` through `runOnMain`; collect results in `DispatchGroup.notify` or a serial queue; copy `parts` into a `let` first.
- **Status (2026-11-05):** qa-build-lint re-read all four sites at HEAD b83be51 and they are unchanged. Every target pins `SWIFT_VERSION: "6.0"` (project.yml:45, :123, :150, :174), while the "build succeeds with warnings" above came from an `.xcodeproj` that was not regenerated from project.yml. A project regenerated from project.yml is in the mode where these diagnostics are errors, so the rating may be too low (re-rate HIGH if they fail). The rest of the code is clearly Swift-6-hardened (`runOnMain`, `nonisolated(unsafe)`, `@unchecked Sendable`), so it may already compile. Unverified without a compiler: run `xcodegen generate` and a device build on the Mac.

#### ISSUE-112: CLAUDE.md still describes a live iOS paywall; dead `premiumSource` and stale comment; Terms gate and update alert undocumented
- **Severity:** LOW
- **Area:** navigation
- **File:** CLAUDE.md ("Known platform divergence", `replaceLobby` sentence, `StripeConfig`/`PaymentWebView` bullet); App/AppRoute.swift:15; Navigation/MaxPlayersView.swift:3-8; App/RootView.swift:41-44, 78-93, 114-130
- **Found by:** qa-navigation-flow (2026-10-28)
- **Description:** There is no `LobbyView`, `SubscriptionManager`, `StripeConfig`, `PaymentWebView` or `AccountView`, no `.lobby` route and no `Router.replaceLobby`; `WelcomeView` sends every premium button to `.onePhoneSelection`, so premium is free on both platforms. `GameSelection.premiumSource` is never set or read, and `MaxPlayersView`'s comment says "right after paying". The first-launch gate now starts with a mandatory `TermsView` (`accepted_terms`; `gateDone` needs both it and the name), and `RootView` owns an App Store "Update available" alert (`dismissed_update_version`); CLAUDE.md describes neither.
- **Suggested fix:** Remove the divergence paragraph, `replaceLobby` sentence and Stripe bullet; delete `premiumSource` and fix the comment; add a paragraph on gate order and the update alert.
- **Status (2026-11-05):** More stale spots than listed above. CLAUDE.md also cites `AccountView.placeholderField` (iOS-14 constraints list, ~line 64); code comments still talk about premium purchases or Stripe in Core/AuthManager.swift:5-9,14, Navigation/LoginView.swift:8, Core/TrustedWebView.swift:4,13,63-74,99-105 (Stripe, `MainWebView`, an unused `onNavigate` interception) and Navigation/MaxPlayersView.swift:3. `GameCatalog.socialItems` (GameCatalog.swift:28) and its dead branch (OnePhoneSelectionView.swift:61) were removed on Android under ISSUE-194. iOS-only pieces missing from the architecture sections: Live Activity (`LiveActivityManager`), the admin local notifications (`AdminFeedbackChecker`, `LocalNotificationManager`, `AdminNotificationTracker`), the App Store update alert (`UpdateChecker`) and `NearbyDisconnectGuard`.

#### ISSUE-113: Live Activity context stays set while "Opponent Disconnected" sits over a dead game
- **Severity:** LOW
- **Area:** navigation
- **File:** App/RootView.swift:197-202; Core/LiveActivityManager.swift:26-30; App/BuddyVerseApp.swift:41-43
- **Found by:** qa-navigation-flow (2026-10-28)
- **Description:** Every route stays mounted, so pushing `.opponentDisconnected` doesn't fire the game's `onDisappear`; `currentContext` stays non-nil and backgrounding on that screen starts a "you vs them" Dynamic Island activity for an ended room.
- **Suggested fix:** Clear `currentContext` where `.opponentDisconnected` is pushed, or treat it as valid only while the game is the top route.

#### ISSUE-114: Covered screens and the first-run gate are still reachable by VoiceOver
- **Severity:** LOW
- **Area:** navigation
- **File:** App/RootView.swift:54-61 and :156-165
- **Found by:** qa-navigation-flow (2026-10-28)
- **Description:** Only `.allowsHitTesting` is applied to buried screens, so VoiceOver and Switch Control can still reach the buried Welcome, game and lobby controls, including behind the Terms/name gate.
- **Suggested fix:** `.accessibilityHidden(!gateDone)` on `mainContent`, `.accessibilityHidden(index != router.path.count - 1)` in the route `ForEach`, and `.accessibilityHidden(!router.path.isEmpty)` on `WelcomeView`.

#### ISSUE-116: Contested trivia answers kept that Android dropped or qualified, and two near-duplicate gas questions
- **Severity:** LOW
- **Area:** content
- **File:** Games/Trivia/TriviaView.swift:566 (South Africa), :568 (Netherlands), :512 (smallest continent), :492 and :530 (carbon dioxide)
- **Found by:** qa-content (2026-10-28)
- **Description:** Android removed the South Africa question as contested (ISSUE-133); on iOS the reworded version is correct but still a trick for kids. Amsterdam as the Netherlands' capital has "Hague" as a distractor some players will call right. "Smallest continent" depends on the 7-continent model. "Which gas do humans breathe out" and "which gas do plants absorb" both answer Carbon Dioxide.
- **Suggested fix:** Drop the South Africa and Netherlands questions (or add "constitutional capital"), and replace one of the gas questions.

#### ISSUE-117: No "still waiting for your friend" timeout in Tic-Tac-Toe, Memory or Count to 21 (Android ISSUE-183, partial port missing)
- **Severity:** MEDIUM
- **Area:** multiplayer
- **File:** Games/TicTacToe/TicTacToeView.swift:185-205, Games/MemoryMatch/MemoryMatchView.swift:203-220, Games/CountTo21/CountTo21View.swift:187-201
- **Found by:** qa-multiplayer (2026-11-05)
- **Description:** Android shows a local toast after 90 s when still waiting for the other player (Tic-Tac-Toe roles unassigned, Memory board empty, Count to 21 at count 0 and not your turn). iOS has none. A player lingering on a lobby/instructions screen keeps heartbeating, so nobody is timed out and the others sit on "Connecting..." or an empty board with no hint; only Back gets them out.
- **Suggested fix:** A 90 s one-shot timer after `setListeners` that shows the same toast text while the waiting condition still holds. No wire change.

#### ISSUE-118: `startGame()` does not re-check that at least 2 players are seated (Android ISSUE-169)
- **Severity:** LOW
- **Area:** multiplayer
- **File:** Core/InternetConnectionManager.swift:420-446; Navigation/OnlineLobbyView.swift:151
- **Found by:** qa-multiplayer (2026-11-05)
- **Description:** Android's transaction refuses to flip to "playing" with fewer than 2 players; iOS only checks `status == "waiting"`. The host's `players.count >= 2` gate uses a possibly stale roster, so a guest's `removeSelf` just before the transaction can start a one-seat Count to 21 or Trek game, and the failure path only `print`s.
- **Suggested fix:** Inside the transaction, return early when the snapshot's `players` has fewer than 2 entries.

#### ISSUE-119: Lobby "Cancel" jumps to Welcome instead of the previous screen
- **Severity:** LOW
- **Area:** navigation
- **File:** Navigation/OnlineLobbyView.swift:60
- **Found by:** qa-navigation-flow (2026-11-05)
- **Description:** Cancel calls `stop()` then `router.popToRoot()`, landing on Welcome rather than `friendTypeChoice`/`maxPlayers` as other screens' Back does. Probably intentional, but inconsistent.
- **Suggested fix:** `router.pop()` if landing on the previous screen is wanted.

#### ISSUE-121: A build without GoogleService-Info.plist crashes at launch, although CLAUDE.md says everything else still works
- **Severity:** MEDIUM
- **Area:** build
- **File:** Navigation/WelcomeView.swift:18; Core/AuthManager.swift:17,22; Core/AppFeedbackService.swift:10-19; App/RootView.swift:204; Core/AdminFeedbackChecker.swift:11-13; App/BuddyVerseApp.swift:16-18; project.yml:24-25; CLAUDE.md "One-time setup"
- **Found by:** qa-multiplayer, qa-navigation-flow (2026-11-05)
- **Description:** `BuddyVerseApp.init` skips `FirebaseApp.configure()` when the gitignored plist is missing, but `WelcomeView` initialises `@State isAdminUser = AuthManager.isAdmin()` on its first render, which calls `Auth.auth()` and raises without a default FirebaseApp. `AppFeedbackService.db` and `AdminFeedbackChecker` also call `Firestore.firestore()` unguarded (the name gate's `submitAppUser`, `incrementPlayCount` on every game launch, feedback/report, the update opt-in). Only `InternetConnectionManager.ensureSignedIn` checks `FirebaseApp.app()`, and its friendly "add GoogleService-Info.plist" message can never show. A fresh checkout, CI run, UI test or archive made without the file compiles (the plist is `optional: true`) and then dies on first launch. Release builds that bundle the plist are unaffected.
- **Suggested fix:** One `FirebaseApp.app() != nil` guard in `AuthManager`, `AppFeedbackService`, `AdminFeedbackChecker` and the Admin Dashboard loaders so they no-op without Firebase (or drop `optional: true` so a missing plist fails the build), and correct the CLAUDE.md sentence.

#### ISSUE-122: Many plain-style Buttons only respond to taps on their words (text-sized tap targets)
- **Severity:** MEDIUM
- **Area:** navigation
- **File:** Navigation/OnlineLobbyView.swift:58,101,113,152; MaxPlayersView.swift:41,55; HangmanModeChoiceView.swift:80; MathSprintSelectionView.swift:43; ComingSoonView.swift:25; LoginView.swift:104; AdminDashboardView.swift:362,372,397; FeedbackReportSheets.swift:62,177; and the Back/Home/Reset rows in Games/TicTacToe (120-153), MemorySequence (74-107), SlidePuzzle (49-82), WordSearch (58-90), MemoryMatch (137-170), MathSprint (92-127), Chess (57-78) and Rps (102-136)
- **Found by:** qa-navigation-flow (2026-11-05)
- **Description:** These apply frame/padding/background/clipShape to the `Button` itself with `.buttonStyle(.plain)` instead of to its label. SwiftUI hit-tests a Button against its label bounds, so only the words respond, not the coloured pill or full-width bar (for example the green "Start Game" bar, the white "Reset Game" bar, and the grey "Back"/"Home" pills at roughly 30x17 pt). The app hit this once already: the comment at TicTacToeView.swift:97-106 says a plain Button "was silently swallowing taps on-device". Reasoned from SwiftUI hit-testing rules, not device-verified; the UI test taps by coordinate so would not catch it. Screens using a label-based Button or `LegacyProminentButtonStyle`/`LegacyBorderedButtonStyle` are fine (OnePhoneSelection, InstructionsChoice, BotDifficulty, Sudoku, Hangman, the Treks, the solo expedition games). The new Chess screen copies this pattern from Slide Puzzle.
- **Suggested fix:** Move frame/padding/background/clipShape inside the label closure and add `.contentShape(Rectangle())`, or reuse the Legacy button styles.

#### ISSUE-123: Volcano Climb: needle speed is uncapped and uses Android's pixel values as points, so late zones are nearly unplayable (the ISSUE-88 fix is not in the code)
- **Severity:** MEDIUM
- **Area:** game-logic
- **File:** Games/VolcanoClimb/VolcanoClimbView.swift:254-264, 287, 290-293, 304, 309-317
- **Found by:** qa-game-logic (2026-11-05)
- **Description:** `currentNeedleStep()` returns `baseNeedleStep * zone.speedMultiplier * streakBonus` with no limit. ISSUE-88 (Fixed) says "needleStep is capped at 40% of the safe-zone width", but no such cap exists in the file. The base steps 8/12/16 are Android's raw pixel values used as points (Jungle Run and Space Explorer divide by 2.75, Volcano doesn't), so the needle crosses about 3x faster than on Android. On a 353 pt track with one tick per 30 ms: HARD zone 4 has a 34.9 pt safe zone against a 30.4 pt step (33.4 at streak 10), so the needle is inside the zone for about one tick per pass and sweeps the whole bar in about 0.34 s; on a 335 pt track (iPhone SE) the step at streak 10 exceeds the zone so the needle can skip it entirely; MEDIUM zone 4 is 50 pt against 22.8 pt per tick; HARD zone 3 is 44 pt against 24.8 pt. Android's same numbers in pixels on a ~1000 px track give about 100 ms windows and 1 s sweeps (VolcanoClimbActivity.kt:116-125, 174-178).
- **Suggested fix:** Re-add the cap (`min(step, safeZoneWidth * 0.4)`) and/or divide the base steps by 2.75 as Jungle and Space do.

#### ISSUE-124: Savanna Safari: Android ISSUE-167 not ported (a tap does not restart the cycle timer, and the animal can repeat)
- **Severity:** MEDIUM
- **Area:** game-logic
- **File:** Games/SavannaSafari/SavannaSafariView.swift:241-270 (`onAnimalTapped`), :272-274 (`randomAnimal`), :313-327 (`scheduleNextCycle`/`cycleAnimal`)
- **Found by:** qa-game-logic (2026-11-05)
- **Description:** After any tap `onAnimalTapped` calls `cycleAnimal()` but leaves the already-running one-shot timer alone, so the fresh animal can be replaced a few milliseconds later and a tap on it then scores as a wrong animal (a strike). On HARD in the last zone the interval is 0.8 x 0.46 = 0.37 s, so a new animal is on screen for about 0.18 s on average. `randomAnimal()` picks from all animals, so one time in seven the animal does not change after a tap, which is the "hammer a lucky correct animal to farm points" case the class comment says is prevented.
- **Suggested fix:** Invalidate and reschedule the timer in `onAnimalTapped` (a `stop()`/`resume()` pair works) and pick from `animals.filter { $0 != currentAnimal }`, as Android does (SavannaSafariActivity.kt:186-195, 238-242).

#### ISSUE-125: Cave Explorer: always choosing Rest means you can never lose (Android open ISSUE-184 applies here too)
- **Severity:** MEDIUM
- **Area:** game-logic
- **File:** Games/CaveExplorer/CaveExplorerView.swift:264-281, 355-399, 409-421
- **Found by:** qa-game-logic (2026-11-05)
- **Description:** Only the player whose action takes `torchLight` to 0 loses, and Rest adds 10-20 (capped at 100), so a player who always rests can never lose and depth plays no part in winning. Against the bot (explores whenever torch is above its HARD 21 / MEDIUM 16 / EASY 10 threshold, losing 10-25) the net drift is about -2.5 per cycle, so the torch walks down into the 22-25 band in roughly 25-30 cycles where the bot's explore kills it: tapping Rest repeatedly is a near-guaranteed win in about a minute. In pass-and-play and online two players who both rest play forever.
- **Suggested fix:** Make depth matter (target depth, a cap on consecutive rests, or torch decay every turn). This changes the resolved TURN numbers or the win rule, so it needs the same change on Android (ISSUE-184 is waiting on that decision).

#### ISSUE-126: Savanna Safari and Jungle Run: HARD last-zone timing floors not ported (Android ISSUE-174)
- **Severity:** LOW
- **Area:** game-logic
- **File:** Games/SavannaSafari/SavannaSafariView.swift:237-239; Games/JungleRun/JungleRunView.swift:203
- **Found by:** qa-game-logic (2026-11-05)
- **Description:** iOS Savanna HARD in Pride Lands cycles every 0.8 x 0.46 = 368 ms, and Jungle HARD in Treetop Canopy gives 800 x 0.55 = 440 ms to find and tap the fruit. Android floors these at 550 ms and 600 ms (`SavannaSafariActivity.kt:77-81`, `JungleRunActivity.kt:70-73`); iOS has no floor.
- **Suggested fix:** Clamp the Savanna cycle interval to at least 0.55 s and the Jungle interval to at least 0.6 s.

#### ISSUE-127: Riddles: "Play Again" redraws from a fresh shuffle, so about two thirds of new rounds repeat a riddle just seen (Android ISSUE-178/192 not ported)
- **Severity:** LOW
- **Area:** content
- **File:** Games/Riddles/RiddlesView.swift:50-59 (`drawRound`), :402-410 (`startNewRound`)
- **Found by:** qa-game-logic (2026-11-05)
- **Description:** `drawRound` builds a local `pool.shuffled()` on every call, so consecutive rounds are independent samples of about 99 riddles; the chance of at least one repeat between two consecutive 10-riddle rounds is about 67%. Trivia already uses a shared static bag (TriviaView.swift:53-77).
- **Suggested fix:** One persistent bag refilled only when empty, putting already-drawn riddles at the front on a mid-round refill, as TriviaView does.

#### ISSUE-128: Word Search: a cancelled drag leaves a stale selection (Android ISSUE-81 only half ported)
- **Severity:** LOW
- **Area:** game-logic
- **File:** Games/WordSearch/WordSearchView.swift:130-134 (`DragGesture`), :137-164, :207-223
- **Found by:** qa-game-logic (2026-11-05)
- **Description:** `checkWord()` runs only in `.onEnded`. If the system cancels the touch (call, Control Center, banner) `.onEnded` never fires, so `selectedCells` stays highlighted and the next drag appends to it; a following single tap then reports "Try again!". Space Explorer and Swamp already solved the same SwiftUI limitation with `@GestureState`.
- **Suggested fix:** Add a `@GestureState` touching flag and clear `selectedCells` when it drops to false without `onEnded` having run.

#### ISSUE-129: Memory Sequence: backgrounding mid-playback collapses the sequence (Android ISSUE-171 not ported)
- **Severity:** LOW
- **Area:** game-logic
- **File:** Games/MemorySequence/MemorySequenceView.swift:155-170, :201-205, :111
- **Found by:** qa-game-logic (2026-11-05)
- **Description:** `playSequence()` schedules every flash and the final "Your Turn!" up front with `asyncAfter`, and only `.onDisappear` cancels them (the file has no `scenePhase` handling). If the app is backgrounded during playback, all overdue flashes fire at once on return, only the last colour is visible and "Your Turn!" appears immediately, so the player must repeat a sequence they never saw.
- **Suggested fix:** On `scenePhase != .active` call `cancelPending()`, reset `sequence` and show "Tap START to try again".

#### ISSUE-130: Math Sprint: the clock keeps running while the app is backgrounded (Android ISSUE-189)
- **Severity:** LOW
- **Area:** game-logic
- **File:** Games/MathSprint/MathSprintView.swift:178-193
- **Found by:** qa-game-logic (2026-11-05)
- **Description:** The timer counts down against a fixed `endDate` (deliberately mirroring CountDownTimer), so switching apps for 10 s in a 30 s sprint costs 10 s and a long switch ends the round on return. Android now pauses on `onPause` and resumes from the remaining time.
- **Suggested fix:** Store the remaining seconds on `scenePhase != .active` and rebuild `endDate` on `.active`.

#### ISSUE-131: Hangman: a stuck picker gives no "tap New to skip" hint, and the race-word resend is narrower than Android's
- **Severity:** LOW
- **Area:** multiplayer
- **File:** Games/Hangman/HangmanView.swift:131-140 (`armSkipTimer`), :370-388, :604-613 (Android HangmanActivity.kt:304-312, :721-730)
- **Found by:** qa-multiplayer, qa-game-logic (2026-11-05)
- **Description:** (a) After 20 s `armSkipTimer()` only sets `skipAvailable`, which silently enables New; `categoryText` stays "Waiting for X to pick a word...". Android also sets "X hasn't picked a word - tap New Word to skip them." (b) On a same-round RESET iOS seat 0 re-sends `RACEWORD` only while `phase == .playing`, nothing has been guessed and the round isn't over; Android re-sends whenever the word is ready (ISSUE-89). If seat 0 has already tapped a letter or finished when the crossing RESET arrives, the other phone stays on "Waiting for a random word..." until its 20 s skip.
- **Suggested fix:** Set `categoryText` in the skip-timer closure when still `.waitingForWord`; drop the extra resend conditions, keeping the same-round and seat-0 checks.

#### ISSUE-132: Hangman does not check that incoming messages come from a room member (Android ISSUE-78, Hangman part)
- **Severity:** LOW
- **Area:** multiplayer
- **File:** Games/Hangman/HangmanView.swift:599-623 and :634-720 (Android HangmanActivity.kt:713-714)
- **Found by:** qa-multiplayer (2026-11-05)
- **Description:** Android drops any message whose `sender` isn't in `players`; iOS has no such check (Count to 21, Memory and the Treks check the turn player instead). A non-member who knows the 6-digit code can inject messages: in PICKER mode a `GUESS` or `RESULT:WIN/LOSE` passes the `!isPicker(sender)` guard, in RACE mode made-up ids in `RESULT:RACEOUT` fill `raceOutIds` until the round ends for everyone, and a `RESET` for round+1..3 restarts the room. The check only shuts out non-members; `sender` is client-written, so a member can still spoof another on either platform.
- **Suggested fix:** At the top of `receiveNearbyMessage`, return if `!players.isEmpty && !players.contains(where: { $0.id == sender })`.

#### ISSUE-133: A lobby guest evicted after backgrounding is told the game ended, though the room and code are still valid (ISSUE-102 residual)
- **Severity:** LOW
- **Area:** multiplayer
- **File:** Core/InternetConnectionManager.swift:768-796; Navigation/OnlineLobbyView.swift:276-290 (message at :283)
- **Found by:** qa-multiplayer (2026-11-05)
- **Description:** A backgrounded iOS guest stops heartbeating; after 90 s a host removes its seat, and on return the lobby says "The game ended. Ask your friend for a new code." The room and code are still valid and the guest could simply rejoin. The 90 s eviction itself is ISSUE-102.
- **Suggested fix:** Tell the guest they were removed while away and can rejoin with the same code; optionally refresh the guest's `lastSeen` on the foreground notification.

#### ISSUE-134: Memory and Hangman avoid the buffered-replay wipe (Android ISSUE-102/103) only because of an undocumented async hop (latent)
- **Severity:** LOW
- **Area:** multiplayer
- **File:** Games/MemoryMatch/MemoryMatchView.swift:203-220; Games/Hangman/HangmanView.swift:286-310; Core/MainActorHelpers.swift:12-18
- **Found by:** qa-multiplayer (2026-11-05)
- **Description:** Android resets round state first and then calls `setListeners`, so a replayed SETUP/WORD isn't wiped. iOS calls `setListeners` first and `beginNearbyRound()` / `restartNearbyRound()` second, which works only because every game callback wraps delivery in `DispatchQueue.main.async`, so buffered replays run after the reset. `runOnMain` executes inline when already on main, so swapping the games' hops to `runOnMain` would make the replay synchronous and wipe a buffered SETUP/WORD, leaving the phone waiting forever (the ISSUE-102/103 symptom). Not a present bug.
- **Suggested fix:** Add a comment at both call sites, or reorder to match Android (non-roller resets before `setListeners`; roller starts after, only if the board is empty).

#### ISSUE-135: The public marketing page docs/index.html still advertises Gemini-generated / AI content
- **Severity:** LOW
- **Area:** content
- **File:** docs/index.html:7 and :258-259
- **Found by:** qa-ai-content (2026-11-05)
- **Description:** The meta description says "26 mini-games plus AI-generated conversation starters", and a feature card titled "AI conversation starters" says "Gemini-generated jokes, riddles, trivia, and conversation prompts to break the ice." Neither platform has any AI path, so this is false, and it contradicts the policy the AI removal was done for (no AI service touching a minor's device). The in-app strings are clean; this page is public-facing.
- **Suggested fix:** Reword to built-in content, for example "Jokes, riddles, trivia and conversation prompts to break the ice", and drop "AI-generated" from the meta description.

#### ISSUE-136: "How to Play" title shows raw GAME_TYPE codes (Android ISSUE-156 never ported)
- **Severity:** LOW
- **Area:** navigation
- **File:** Navigation/InstructionsScreenView.swift:66
- **Found by:** qa-navigation-flow (2026-11-05)
- **Description:** The title renders `"How to Play \(selection.gameType)"`, giving "How to Play COUNT21", "WORDSEARCH", "TICTACTOE", "SEQUENCE" and so on. Android uses the display name (InstructionsViewActivity.kt:46) and iOS already has the helper at Core/AppFeedbackService.swift:44.
- **Suggested fix:** Use `AppFeedbackService.displayName(for: selection.gameType)`.

#### ISSUE-137: Widget deep link replaces the whole navigation stack, destroying a paused game (Android keeps it)
- **Severity:** LOW
- **Area:** navigation
- **File:** App/RootView.swift:99-110
- **Found by:** qa-navigation-flow (2026-11-05)
- **Description:** `consumePendingDeepLink()` ends any live room and sets `router.path = [route]` unconditionally, dropping whatever game was open, including solo progress. Android deliberately stopped doing this (ISSUE-127): the widget uses `FLAG_ACTIVITY_NEW_TASK` only and `DailyQuestionActivity` finishes back to the running app. The practical window is small because the user has to background the app to reach the widget. This file documents the replacement as intended but not that it differs from Android.
- **Suggested fix:** Push `.dailyQuestion` on top when the stack holds a game and replace only when the stack is empty or holds no running game; if replacement is kept, record the divergence in CLAUDE.md.

#### ISSUE-138: The UI test cannot get past the first-launch Terms/Name/GetUpdates gate on a clean install
- **Severity:** LOW
- **Area:** build
- **File:** BuddyVerseUITests/BuddyVerseUITests.swift:18-22
- **Found by:** qa-navigation-flow (2026-11-05)
- **Description:** The test launches and goes straight to the Welcome cards. On a fresh simulator or CI run `RootView` shows the gate over Welcome and disables hit-testing on `mainContent` (RootView.swift:54-61). The "Explore the app" button still exists in the accessibility tree so the first assertion passes, then the card tap is swallowed by the overlay and the test fails later with a misleading "OnePhoneSelection screen didn't load". It only works on a simulator that was already clicked through by hand. (It would also hit ISSUE-121 on a build without the Firebase plist.)
- **Suggested fix:** Set `app.launchArguments += ["-accepted_terms", "YES", "-has_entered_name", "YES"]` before `launch()`.

#### ISSUE-139: Count to 21's "Back to Welcome" button only goes back one screen
- **Severity:** LOW
- **Area:** navigation
- **File:** Games/CountTo21/CountTo21View.swift:125
- **Found by:** qa-navigation-flow (2026-11-05)
- **Description:** Android's label is accurate because its intermediate screens finish, so Back lands on Welcome. On iOS `router.pop()` returns to BotDifficulty, InstructionsChoice or FriendTypeChoice; a separate "Home" button already exists.
- **Suggested fix:** Rename it "Back" or "Back to Menu", as the other games do.

#### ISSUE-140: Redundant `#available(iOS 15...)` checks and stale "14.0 floor" comments after the deployment-target bump
- **Severity:** LOW
- **Area:** build
- **File:** Core/LocalNotificationManager.swift:51; Games/MathSprint/MathSprintView.swift:85; stale comments at Core/BuddyVerseActivityAttributes.swift:10-11, Core/LiveActivityManager.swift:23-24, Core/LocalNotificationManager.swift:48-50, App/RootView.swift:12, Core/LegacyButtonStyles.swift:5, Games/MathSprint/MathSprintView.swift:79-83
- **Found by:** qa-build-lint (2026-11-05); expected compiler warnings, not observed (no compiler available)
- **Description:** The floor is 15.0 (project.yml:5 and :17), so `#available(iOS 15.0, *)` and `#available(iOS 15, *)` are always true and the Swift compiler normally warns "unnecessary check for 'iOS'". The `else { answerField }` branch at MathSprintView.swift:87-89 is now dead code.
- **Suggested fix:** Drop the two checks (the "iOS 14 compatibility constraints" section says the iOS 15 items may now be relaxed) and refresh the comments.

#### ISSUE-141: The qa-build-lint agent spec says never use a simulator, but CLAUDE.md says simulators are allowed
- **Severity:** LOW
- **Area:** build
- **File:** .claude/agents/qa-build-lint.md:3 and :9; CLAUDE.md "Commands"
- **Found by:** qa-build-lint (2026-11-05)
- **Description:** The agent spec says "no simulator ... the owner has said no simulators. Compile only", while CLAUDE.md says "Simulators are allowed. The old no-simulator rule existed because an earlier computer was short on disk space". The agent followed the stricter rule, so UI and unit tests are never run by the QA pass.
- **Suggested fix:** Update the agent spec to match CLAUDE.md (or restore the rule if it still stands).

#### ISSUE-142: iOS side of Android ISSUE-203/204: the math-teacher joke has no pun, and the Conversation screen promises other people's answers
- **Severity:** LOW
- **Area:** content
- **File:** Games/Jokes/JokesView.swift:382; Games/Conversation/ConversationView.swift:173 and :181; Navigation/InstructionsScreenView.swift:38
- **Found by:** qa-ai-content (2026-11-05)
- **Description:** Same text and the same problems as the Android entries: the "sine and cosine" beach joke doesn't land, and "What others are saying:" / "yours could be the first!" describe answers that are only the ones typed on this phone.
- **Suggested fix:** See Android ISSUE-203 and ISSUE-204; make the same edits here.

### Fixed

#### ISSUE-120: Chess bot could leave the board locked on "Bot is thinking..." after the view disappeared
- **Severity:** LOW
- **Area:** game-logic
- **Found by:** qa-game-logic (2026-11-05)
- **Fixed by:** main agent on 2026-11-05
- **Summary:** `ChessView.onDisappear` bumped `gameId` to drop a pending bot move, but the bot's callback returns before clearing `botThinking` when `gameId` has changed, so a disappear/reappear froze input until New Game. `onDisappear` now clears `botThinking` as well. Not run on a device (the chess code has never been compiled; see the Chess section).


#### ISSUE-36: RPS MEDIUM/HARD bots see the player's pick before choosing (Android ISSUE-76)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** MEDIUM/HARD bots now only counter the player's PREVIOUS throw (40%/60%), otherwise random; EASY fully random.

#### ISSUE-37: Sudoku 'Check' celebrates a solve after 'Answer' was used (Android ISSUE-80)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `checkBoard()` returns early with a toast when `answerRevealed` is true.

#### ISSUE-38: Tic-Tac-Toe online: a win racing a manual Reset permanently desyncs who moves first (Android ISSUE-86)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Nearby opener derives from `roundId % 2` (`xStartsThisRound`); the toggled `xStartsNext` state was removed (Android ISSUE-86).

#### ISSUE-39: Tic-Tac-Toe online: Reset before the HELLO handshake completes leaves a phone on 'Connecting...' (Android ISSUE-74)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `onResetPressed()` is a no-op in nearby mode until `roleAssigned` (Android ISSUE-74).

#### ISSUE-40: Hangman PICKER: 'New' enabled mid-round desyncs picker rotation (Android ISSUE-61)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** New is disabled online until `roundOver` (`newEnabled`), so two phones can't diverge on the picker (Android ISSUE-61).

#### ISSUE-41: Hangman online: no way to skip an idle picker, and a simultaneous New can strand a RACE phone (Android ISSUE-105, ISSUE-89)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** A 20s `armSkipTimer` lets a stuck guesser use New to skip an idle picker; sender and receivers rotate once via `rotatePickerIfSkipping()`; seat 0 re-sends the identical RACEWORD on a same-round RESET (Android ISSUE-105/89).

#### ISSUE-42: Difficulty picker for Riddles, Trivia and Conversation has no effect (Android ISSUE-62)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `MoodSelectionView` routes every game straight to the age-group screen with a placeholder MEDIUM difficulty; `DifficultySelectionView` is now orphaned (documented under Known platform gaps).

#### ISSUE-43: Backing out of an interstitial screen never calls stop(), so the room stays alive and the others hang
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Back on `InstructionsChoiceView` (when nearby) and on `HangmanModeChoiceView` now calls `InternetConnectionManager.shared.stop()` before popping. Back on the instructions screen itself only returns to the choice screen, so it keeps the room.

#### ISSUE-44: Memory: REVEAL applied before a board exists can trap on an empty shuffledIcons
- **Fixed by:** main agent on 2026-10-15
- **Summary:** The REVEAL handler guards `boardReady` and `shuffledIcons.count == 12`.

#### ISSUE-45: Hangman isPlainLetter accepts a base letter plus a combining mark
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `isPlainLetter` requires exactly one unicode scalar in 0x41...0x5A.

#### ISSUE-46: Join failure can show raw Firestore error text
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Join failures from our own transaction keep their message; any other error shows `describeFirestoreFailure`.

#### ISSUE-47: Firestore rules caveat: the heartbeat needs any room member to be able to update lastSeen.<id>
- **Fixed by:** main agent on 2026-10-15
- **Summary:** The heartbeat now uses `FieldPath(["lastSeen", id])`. The rules question itself cannot be answered from the repo - **owner must confirm in the Firebase console** that any room member may update `lastSeen.*`. Left as an owner action.

#### ISSUE-48: Hangman: every guesser rebroadcasts RESULT:WIN/LOSE for a mirrored guess (Android ISSUE-63)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `checkGameStatus(announce:)` - the GUESS-mirroring call passes `announce: false`, so only the guesser whose tap ended the round sends RESULT (Android ISSUE-63).

#### ISSUE-49: Storm Chase failure message overstates rounds survived by one
- **Fixed by:** main agent on 2026-10-15
- **Summary:** The message uses `max(round - 1, 0)`, with a special line for failing the first round.

#### ISSUE-50: Swamp Trek: an interrupted hold is never reset (Android ISSUE-99 intent)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** The hold gesture tracks a `@GestureState isTouching`; if it goes false while `isHolding` is still true (cancelled) the hold is dropped without scoring (Android ISSUE-99).

#### ISSUE-51: Unknown game type silently opens Tic-Tac-Toe (Android ISSUE-82)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `GameRouter`'s default now shows `ComingSoonView(gameName:)` instead of Tic-Tac-Toe (Android ISSUE-82).

#### ISSUE-53: Welcome stats claim '100+' jokes, riddles and trivia but the pools are smaller
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Jokes grown to 103, riddles to 102 and trivia to 101 (all-ages, de-duplicated by answer or text), so the '100+' cards are accurate for all three.

#### ISSUE-54: Riddle pool has a death-themed riddle and an ambiguous pair
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Removed the coffin riddle and the hurricane twin of the needle riddle.

#### ISSUE-55: Joke pool still has weak filler (sham-poo, Fsh, A fishy, B., chili dog, ladder/shovel/flashlight cluster)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Removed 8 weak or template jokes (sham-poo, Fsh, A fishy, B., chili dog, ladder/shovel/flashlight).

#### ISSUE-56: Trivia 'Father of Computers' is debatable
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Replaced the Alan Turing distractor with Thomas Edison.

#### ISSUE-57: Conversation starters contain near-duplicates and some adult-leaning prompts
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Removed 7 near-duplicate or adult-leaning starters (travel memory, comfort food, advice to younger self, concert, charity, family memory, local business) and added 5 kid-friendly ones.

#### ISSUE-58: Stale NavigationStack comments in AppRoute.swift
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Comments now describe `Router.path`, `router.push` and `router.pop()`.

#### ISSUE-59: CLAUDE.md says replaceTop is only for no-choice screens but the code uses it more widely
- **Fixed by:** main agent on 2026-10-15
- **Summary:** CLAUDE.md now lists the intentional `replaceTop` uses and documents `replaceLobby`.

#### ISSUE-60: Background music file is not bundled (silent, guarded)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Documented under 'Known platform gaps'; the file itself is an asset only the owner can supply.

#### ISSUE-1: Count to 21 vs bot softlocks whenever the bot has to open a round
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `resetGame()`'s non-nearby branch now schedules `botMove()` after 1s when `isBotGame && !isPlayerTurn`. Also made nearby opener derive from `roundId % players.count` (Android ISSUE-86) and bounded RESET to `roundId+1...+3`.

#### ISSUE-2: LobbyView paywall reappears after a successful payment or entitlement
- **Fixed by:** main agent on 2026-10-15
- **Summary:** New `Router.replaceLobby(with:)` removes the Lobby entry and everything above it (Account/payment screens) before pushing the game picker; used by the payment-success handler and `proceedEntitled()`, which now only acts if the Lobby is still on top.

#### ISSUE-3: Online games leave a stale OnlineLobbyView under the game
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `OnlineLobbyView.onGameStarted` now `replaceTop`s with the instructions/mode-choice screen instead of pushing on top of the lobby.

#### ISSUE-4: navigationTitle / navigationBarTitleDisplayMode are no-ops without a NavigationView
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Removed every no-op `.navigationTitle` / `.navigationBarTitleDisplayMode` modifier (there is no navigation bar).

#### ISSUE-5: CLAUDE.md drift: GoogleService-Info.plist exists; Secrets.plist reference is stale
- **Fixed by:** main agent on 2026-10-15
- **Summary:** CLAUDE.md now says the plist is present and documents the no-simulator rule; the stale `Secrets.example.plist` comment in `BuddyVerseApp.swift` was fixed. `Secrets.plist` itself is tracked as ISSUE-11.

#### ISSUE-6: Dead AI plumbing (aiItems) and stale 'AI generation' comments
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Removed `GameSelection.aiItems`, the `AiGeneratingView` assignment, the JSON-decode `buildPool` branches in all four content views, and the stale 'AI generation' comments. `premiumSource` is NOT dead (PaymentWebView sets it) and was kept.

#### ISSUE-7: Trivia answer options never shuffled (Android ISSUE-100 regression)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `drawRound` now shuffles each question's options (answer checking compares text, not position).

#### ISSUE-8: Riddle pool has ~14 repeated riddles and one garbled riddle
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Riddle pool deduplicated by answer (64 -> 48) and the garbled keyboard riddle removed (the clean wording is kept).

#### ISSUE-9: Joke pool has near-duplicates and filler that is not a joke
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Removed 20 joke entries: the second scarecrow, second golfer, 'sham-rock' flower copy, 'lean beef' copy, and weak oven/fridge/toaster/compass/ruler/map filler.

#### ISSUE-10: Trivia has a duplicate question and ambiguous answers
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Removed the duplicate 'continents' and Hawaii/Pacific questions; reworded most-spoken-language (native speakers), South Africa (executive capital), light bulb ('most famously credited') and shark bones (hint added).

#### ISSUE-13: AdminDashboardView does not check isAdmin() itself
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `AdminDashboardView.onAppear` now returns to the previous screen unless `AuthManager.isAdmin()`.

#### ISSUE-14: Hangman custom word can contain non-A-Z letters, making the round unwinnable
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Own word input and incoming WORD/RACEWORD are A-Z only, 2-20 letters (category <= 30) via `isPlainLetter` / `isValidWireWord`.

#### ISSUE-15: Math Sprint accepts answers after time is up; delayed pop can eject from the wrong screen
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Added a `gameOver` flag: input is guarded, question/answer/SUBMIT are replaced by a persistent 'Time's Up! Final Score' line, and the automatic delayed `router.pop()` was removed.

#### ISSUE-16: Slide Puzzle shuffle can end solved; tiles stay tappable after a win
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `shuffleBoard()` re-walks (up to 10 times, then forces one move) until not solved; a `puzzleSolved` flag blocks taps after a win until the next shuffle.

#### ISSUE-17: Word Search always places the word horizontally from column 0
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Word placement is now random across/down at a random start that fits; the 'Try again!' toast only fires for selections of more than one cell.

#### ISSUE-18: Memory Match pass-and-play never declares a winner
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Pairs are credited per side in bot and pass-and-play, and the end message names the winner or a tie (confetti only for a human/player win).

#### ISSUE-19: No heartbeat or presence (Android ISSUE-106/91/117)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Ported `startHeartbeat` / `trackPeerHeartbeats` / `checkPresence` / `handleConnectionLost` with Android's constants and a `CLOCK_MONOTONIC_RAW` clock; the room doc is created with `lastSeen`. Needs a device test and Firestore rules that allow `lastSeen.<id>` updates by any room member.

#### ISSUE-20: A guest leaving mid-game stalls everyone (Android ISSUE-69)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `listenToRoom` now detects a known player vanishing while the room is 'playing' and calls `onDisconnected`.

#### ISSUE-21: Listener errors, missing room doc and failed sends never end the session (Android ISSUE-90/91)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Listener errors, a server-confirmed missing room doc, and `sendMessage` write failures all go through `handleConnectionLost`.

#### ISSUE-22: No background grace period when the app is suspended (Android ISSUE-85)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** iOS suspends the app, so the 60s grace is checked on return to the foreground (`backgroundedAt` + `handleReturnedToForeground`): past 60s the session is stopped and `onDisconnected` fires. Other phones notice via the heartbeat.

#### ISSUE-23: startGame() is not a transaction and does not freeze startedPlayers (Android ISSUE-115)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `startGame()` is now a transaction from 'waiting' that also writes `startedPlayers`; the lobby builds the game's roster from `playersForGame()`.

#### ISSUE-24: Room-code creation is not transactional (Android ISSUE-94)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Room creation runs the existence check and write in one `runTransaction`, retrying on a taken code.

#### ISSUE-25: Join validation gaps: no 6-digit check, no host lastSeen TTL (Android ISSUE-55/106)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `joinRoom` rejects anything but exactly 6 ASCII digits before touching Firestore, and the join transaction rejects a room whose host `lastSeen` is over 3 minutes old.

#### ISSUE-26: No sender-identity checks in any game (Android ISSUE-60/78/109)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `setListeners(... onMessageWithSender:)` added (exactly one callback per message). Count to 21 (MOVE), Memory (SETUP from seat 0 only while waiting; REVEAL from the turn player), Hangman (WORD/RACEWORD/GUESS/RESULT per role) and Arctic/Cave/Desert (TURN actor == sender == turn player) now verify senders.

#### ISSUE-27: Out-of-range remote numbers can crash or wedge Arctic/Desert/Cave (Android ISSUE-59)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Arctic, Cave and Desert drop TURN messages whose numbers fall outside the sender's own dice ranges.

#### ISSUE-28: Memory REVEAL dropped while isProcessing causes multi-player desync (Android ISSUE-87)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** REVEALs arriving during the flip-back timer are queued (max 4) and drained after the timer or a match; also re-sends the identical SETUP when seat 0 gets a same-round RESET on an untouched board (Android ISSUE-89).

#### ISSUE-29: Interstitial screens have no disconnect listener (Android ISSUE-116)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** New `guardNearbyDisconnect` modifier (`Core/NearbyDisconnectGuard.swift`) on HangmanModeChoice, InstructionsChoice and InstructionsScreen registers `setInterstitialDisconnectListener` and routes to the 'friend left' screen.

#### ISSUE-30: Hangman race tie-break not ported (Android ISSUE-96/119)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** New `raceWinnerSeat`: a later RACEWIN from a lower seat overrides an earlier one (including this phone's own claimed win), so everyone settles on the lowest seat.

#### ISSUE-31: Hangman GUESS can 'win' an empty word
- **Fixed by:** main agent on 2026-10-15
- **Summary:** GUESS is ignored unless a word is set and the phase is playing/spectating (and the sender is a guesser, not the picker).

#### ISSUE-32: Unbounded roundId on RESET and no payload size caps (Android ISSUE-120)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** RESET is accepted only when the round moves forward by 1-3 in Tic-Tac-Toe, Count to 21, Memory and Hangman; word and category lengths are capped (see ISSUE-14).

#### ISSUE-33: Host stop() cleanup batch can exceed 500 writes (Android ISSUE-121)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `stop()` deletes messages in batches of 400 and the room doc in its own final batch.

#### ISSUE-34: Lobby disconnect handler only changes text and ignores a joined guest
- **Fixed by:** main agent on 2026-10-15
- **Summary:** New `onLobbyDisconnected`: once joined, a lost room stops the session, clears the roster and returns to the name screen with a message; the old text is kept only if the player never got in.

#### ISSUE-35: Tic-Tac-Toe accepts MOVE regardless of role or turn (Android ISSUE-78)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** MOVE is applied only when roles are assigned and it is the opponent's turn (`roleAssigned, xToMove != amX`).

#### ISSUE-61: Daily pick only ever reached 10 of 30 entries per kind
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `dayOfYear % 3` chose the kind and `dayOfYear % 30` the entry, so only every third index was reachable. The entry is now `(dayOfYear / 3) % count` (Android identical). (File: Core/DailyContentPool.swift)

#### ISSUE-62: Widget deep link wiped the nav stack without ending a live room; cold-launch/name-gate handling
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `consumePendingDeepLink()` stops the `InternetConnectionManager` session when the stack holds an online/nearby screen, is also run on appear (cold launch), and is held until the name gate is finished. `DeepLinkManager` is now `@MainActor` with a plain `static let`. (File: App/RootView.swift)

#### ISSUE-63: Cave Explorer MEDIUM/HARD bots could never run out of light
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Thresholds 35/55 -> MEDIUM 19 / HARD 24 / EASY 10, all below one explore's max cost (25), so every bot can lose (Android identical). (File: Games/CaveExplorer/CaveExplorerView.swift)

#### ISSUE-64: Word Search: dragging just off the grid selected an edge cell, and a grazed neighbour failed a correct word
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Negative points are rejected before dividing, and `checkWord()` accepts the word's cells (or reverse) as a contiguous run in the selection. (File: Games/WordSearch/WordSearchView.swift)

#### ISSUE-65: Sudoku: board stayed editable and the celebration re-fired after a solve
- **Fixed by:** main agent on 2026-10-15
- **Summary:** New `puzzleSolved` state: set on a valid Check, locks the grid and Check, cleared in `startNewGame()`. (File: Games/Sudoku/SudokuView.swift)

#### ISSUE-66: Race-mode Hangman: a racer who ran out of lives could restart the round for everyone
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `newEnabled` in RACE mode needs a RACEWIN or every racer out. A loser broadcasts `RESULT:RACEOUT` (new, mirrored on Android), and all phones track `raceOutIds`; the round ends for everyone when all racers are out. (File: Games/Hangman/HangmanView.swift)

#### ISSUE-67: Arctic/Cave/Desert Trek had no skip for an idle-but-connected player
- **Fixed by:** main agent on 2026-10-15
- **Summary:** After 45 s of someone else's turn the turn label is tappable ("tap here to skip"); `SKIP:<id>` is applied identically on every phone only while it is still that player's turn (Android identical). (File: Games/*Trek*/, CaveExplorer)

#### ISSUE-68: Connection manager: cancelled-join removeSelf on a rejected join, evicted-guest ghost, repeated `ended`, leftover room doc
- **Fixed by:** main agent on 2026-10-15
- **Summary:** removeSelf only runs for a join that actually committed; a guest whose seat was evicted is treated as a lost connection; `ended` fires `onDisconnected` once; a createRoom cancelled in flight deletes its doc; the TTL error mentions automatic date & time. (File: Core/InternetConnectionManager.swift)

#### ISSUE-69: Count to 21 showed totals above 21
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Counter and toasts use `min(currentCount, 21)`. (File: Games/CountTo21/CountTo21View.swift)

#### ISSUE-70: Stale comments and no-op `.navigationBarHidden` in the new Daily Question code
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Comments now describe `buddyverse://daily/question`; the no-op modifier was removed. (File: project.yml, Navigation/DailyQuestionView.swift, Core/DailyContentPool.swift)

#### ISSUE-71: Guest roster showed the guest's own stepper value as the room cap
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Only the host sees "N / max joined"; guests see "N joined" (Android identical). (File: Navigation/OnlineLobbyView.swift)

#### ISSUE-73: Trek SKIP racing the skipped player's own TURN desynced the shared pool
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `applySkip` records `lastSkippedId`; one TURN from that player arriving after the skip is applied (numbers only, `advanceTurn: false`) instead of dropped. Android identical. (Games/*Trek*, CaveExplorer)

#### ISSUE-74: Race Hangman: an idle still-connected racer could keep out racers locked out of New
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `raceOutUnlocked` opens New 60 s after this racer went out with no winner announced (Android identical). (Games/Hangman/HangmanView.swift)

#### ISSUE-75: Hangman PICKER: a stale skip offer kept New enabled mid-round for the new picker
- **Fixed by:** main agent on 2026-10-15
- **Summary:** `restartNearbyRound()` clears `skipAvailable`/`skipToken`. (Games/Hangman/HangmanView.swift)

#### ISSUE-76: Cave Explorer HARD bot was still practically unbeatable (threshold 24)
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Thresholds are now HARD 21 / MEDIUM 16 / EASY 10 (Android identical). (Games/CaveExplorer)

#### ISSUE-77: Word Search: a fast or wobbly drag skipped a letter and failed a correct word
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Cells between two sampled touch points are filled along the straight line (Android identical). (Games/WordSearch)

#### ISSUE-78: Bot-mode round-over text read "You LOSES!"
- **Fixed by:** main agent on 2026-10-15
- **Summary:** "You LOSE" vs "<name> LOSES". (Arctic/Cave/Desert)

#### ISSUE-79: Deep link edge cases: trailing slash, mid-checkout, stale daily pick
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Trailing slashes are trimmed; the link is ignored while the payment screen is on top; `DailyQuestionView.pick` is computed and the answer re-hides on appear. (Core/DeepLinkManager.swift, App/RootView.swift, Navigation/DailyQuestionView.swift)

#### ISSUE-80: Name gate had no input limits; user_first_name was write-only
- **Fixed by:** main agent on 2026-10-15
- **Summary:** First-name fields reject `@` and anything over 30 characters; Get Updates is prefilled from the stored name. (Navigation/EnterNameView.swift, GetUpdatesView.swift)

#### ISSUE-81: autoPublishUpdateIfNewer comment claimed it left the message untouched
- **Fixed by:** main agent on 2026-10-15
- **Summary:** It deliberately clears the previous "what's new" message when a newer version is published (the text described the old version); comment fixed on both platforms. (Core/AppFeedbackService.swift)

#### ISSUE-82: Pool polish: "Father of Computers"/"longest river" wording, relationship joke
- **Fixed by:** main agent on 2026-10-15
- **Summary:** Qualifiers added; the gym/relationship joke removed. (Games/Trivia, Games/Jokes)

#### ISSUE-83: Lobby host lost the room after 60 s in the background
- **Severity:** MEDIUM
- **Area:** multiplayer
- **Found by:** /test-app fifth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** handleReturnedToForeground now tears the session down only when the room is "playing"; a lobby host pasting the code into Messages keeps the room (matches Android, whose grace runs only from game screens).

#### ISSUE-84: autoPublishUpdateIfNewer treated a failed read as "nothing published"
- **Severity:** MEDIUM
- **Area:** content
- **Found by:** /test-app fifth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** The getDocument handler now returns on error / missing doc, so an old build can no longer downgrade appConfig/latest.

#### ISSUE-85: Weak riddles and filler jokes
- **Severity:** MEDIUM
- **Area:** content
- **Found by:** /test-app fifth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** Removed the nonsense "dog" riddle, the overlapping cloud/deck-of-cards/legs riddles, "jumps higher than a house" and the five-letter Stone riddle; added milk-truck, tongue and 13-hearts riddles. Removed seven template jokes, fixed the penguin punchline, added six jokes. Kangaroo/hummus trivia distractors tidied.

#### ISSUE-86: Math Sprint rejected answers with a stray space
- **Severity:** MEDIUM
- **Area:** game-logic
- **Found by:** /test-app fifth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** Answer is trimmed before Int().

#### ISSUE-87: Tic-Tac-Toe wiped the board on the winning move
- **Severity:** LOW
- **Area:** game-logic
- **Found by:** /test-app fifth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** Bot and pass-and-play now keep the finished board for 1.6 s (input locked via roundOver) before resetting; nearby still resets at once to stay in lock-step.

#### ISSUE-88: Volcano Climb needle speed unbounded
- **Severity:** LOW
- **Area:** game-logic
- **Found by:** /test-app fifth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** needleStep is capped at 40% of the safe-zone width.

#### ISSUE-89: Small content/admin fixes
- **Severity:** LOW
- **Area:** content
- **Found by:** /test-app fifth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** Feedback Submit trims newlines; admin counts show "50+" at the query limit; no dangling dash in "Currently live"; name gate rejects digits; Conversation card copy no longer promises other people's answers; HangmanModeChoice ignores a late word-mode callback unless it is still the top screen.

#### ISSUE-92: Duplicate jokes added last round; stat cards overstated
- **Severity:** MEDIUM
- **Area:** content
- **Found by:** /test-app sixth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** Removed the four re-added exact duplicates and the near-duplicate cookie joke; Jokes/Riddles stat cards now count to 90.

#### ISSUE-93: Host suspended in lobby dropped guests after 90 s
- **Severity:** MEDIUM
- **Area:** multiplayer
- **Found by:** /test-app sixth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** Guests now allow the lobby host 300 s of heartbeat silence while the room is "waiting" (iOS suspends a backgrounded host).

#### ISSUE-94: Name gate accepted full names; feedback text unbounded
- **Severity:** LOW
- **Area:** content
- **Found by:** /test-app sixth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** Names must be one word, <= 20 chars, no digits/@; feedback and report text capped at 500 chars with a "no names or contact info" hint.

#### ISSUE-95: Daily pool: weak riddle and contested continents question
- **Severity:** LOW
- **Area:** content
- **Found by:** /test-app sixth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** Replaced "bottom at the top" with the 13-hearts riddle and reworded the continents question, identically on both platforms.

#### ISSUE-96: Bot-win confetti, Jungle Run stale size, stale nav modifiers/comment
- **Severity:** LOW
- **Area:** game-logic
- **Found by:** /test-app sixth pass (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** No confetti when the bot wins; Jungle Run timer follows the current screen size; removed 34 no-op navigationBar modifiers; TicTacToe comment corrected; Trek local turn clears lastSkippedId.

#### ISSUE-99: Ghost seat when a guest leaves in the same snapshot window as Start Game
- **Severity:** MEDIUM
- **Area:** multiplayer
- **Found by:** /test-app seventh pass, Android findings ported (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** InternetConnectionManager treats a startedPlayers seat missing from players, seen as the room flips to playing, as a disconnect (ghostSeat). Ported from Android.

#### ISSUE-100: Conversation answer lost on Back/Home; reshuffle repeats last item; '|||' in answers
- **Severity:** LOW
- **Area:** content
- **Found by:** /test-app seventh pass, Android findings ported (2026-10-17)
- **Fixed by:** main agent on 2026-10-17
- **Summary:** Back/Home save the typed answer; Jokes and Conversation swap the first item after a reshuffle if it repeats the last one shown; '|||' is replaced in saved answers. Ported from Android.

#### ISSUE-101: Auto-lock suspends the app and drops idle online players
- **Severity:** MEDIUM
- **Area:** multiplayer
- **Found by:** qa-multiplayer (2026-10-28)
- **Fixed by:** fixer agent on 2026-10-28
- **Summary:** New private `keepScreenAwake(_:)` sets `UIApplication.shared.isIdleTimerDisabled` through `runOnMain`: turned on right after `connected = true` in both the room-created and room-joined paths, and turned off in every session-ending path (roster-loss disconnect, room "ended", `handleConnectionLost`, `stop()`). No wire change. Auto-lock behavior itself not tested on a device.

#### ISSUE-103: Space Explorer stops responding for the rest of the run if a touch is cancelled
- **Severity:** MEDIUM
- **Area:** game-logic
- **Found by:** qa-game-logic (2026-10-28)
- **Fixed by:** fixer agent on 2026-10-28
- **Summary:** `touchActive` is now a `@GestureState` set through `.updating`, so it resets by itself when a touch ends or the system cancels it; a small `@State touchHandled` flag, cleared by `.onChange(of: touchActive)`, keeps the "first touch event only" behavior. `.onEnded` removed. Not tried with a real cancelled touch.

#### ISSUE-104: Tic-Tac-Toe HARD bot runs full minimax on the main thread over a `[String]` board
- **Severity:** MEDIUM
- **Area:** game-logic
- **Found by:** qa-game-logic (2026-10-28)
- **Fixed by:** fixer agent on 2026-10-28
- **Summary:** `getBestMove()` copies the String board into an `[Int]` (0 empty, 1 X, 2 O) and `minimax` searches that with a new `intWins` check over the existing `winLines`; same algorithm, scoring and tie-breaking (alpha-beta deliberately left out so move choice is identical). MEDIUM/EASY and multiplayer untouched. Perfect play is reasoned, not tested, and the speedup is not measured.

#### ISSUE-105: Riddle pool has re-added duplicates (towel and teapot twice each)
- **Severity:** MEDIUM
- **Area:** content
- **Found by:** qa-content (2026-10-28); Android has the same pairs (ISSUE-168)
- **Fixed by:** fixer agent on 2026-10-28
- **Summary:** Deleted the second towel ("gets wetter the more it dries") and second teapot ("begins with T") riddles; no replacements added; the rest of the pool was not re-checked for other duplicate answers. Pool is now 99 entries.

#### ISSUE-106: Joke pool regressed to filler that earlier fixes removed
- **Severity:** MEDIUM
- **Area:** content
- **Found by:** qa-content (2026-10-28)
- **Fixed by:** fixer agent on 2026-10-28
- **Summary:** Removed Fsh, the chili dog, lean beef, sham rock, the blueberry joke and the umbrella "outstanding in the rain" joke (ladder, flashlight and laughing stock kept). Pool is now 97 entries.

#### ISSUE-115: Welcome stat cards count to 100 but ISSUE-92 says 90
- **Severity:** LOW
- **Area:** content
- **Found by:** qa-content / qa-navigation-flow (2026-10-28)
- **Fixed by:** main agent on 2026-10-28
- **Summary:** Jokes and Riddles Welcome cards now count to 90 (both pools are under 100 after ISSUE-105/106); Trivia stays at 100 (about 101 entries). Code and the ISSUE-92 text now agree.

#### ISSUE-143: Privacy manifest did not declare the System Boot Time API that the Chess bot uses
- **Severity:** MEDIUM
- **Area:** build
- **File:** BuddyVerse/Resources/PrivacyInfo.xcprivacy; BuddyVerse/Games/Chess/ChessEngine.swift:409,416
- **Found by:** qa-build-lint (2026-11-05)
- **Fixed by:** main agent on 2026-11-05
- **Summary:** The Chess bot's time limit calls `ProcessInfo.processInfo.systemUptime`, which Apple lists as a required-reason API (`NSPrivacyAccessedAPICategorySystemBootTime`), but the manifest declared only UserDefaults / CA92.1, so the next App Store Connect upload would likely be flagged (ITMS-91053, missing API declaration). Added the `NSPrivacyAccessedAPICategorySystemBootTime` entry with reason `35F9.1` (measuring elapsed time inside the app) and updated the "App Store setup" note. The manifest still parses (checked with plistlib). The other time source, `clock_gettime_nsec_np` in `InternetConnectionManager`, is not on Apple's list. Not run through App Store Connect.

#### ISSUE-144: Welcome "Original games" counter stopped at 22 after Chess was added
- **Severity:** LOW
- **Area:** navigation
- **File:** Navigation/WelcomeView.swift:419
- **Found by:** qa-navigation-flow (2026-11-05)
- **Fixed by:** main agent on 2026-11-05
- **Summary:** Welcome offers 12 free games (Chess and Math Sprint included) plus 11 expeditions, which is 23, and Android's counter counts to 23. `animateStats()` still counted to 22; it now counts to 23. The prose in ISSUE-92/115 ("jokes/riddles cards count to 90") is stale: both platforms' code counts the Jokes, Riddles and Trivia cards to 100, which matches the current pools (about 104/103/101), so only the text is out of date.
