# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

BuddyVerse (iOS) is a native SwiftUI port of the Android BuddyVerse app (sibling project at `~/AndroidStudioProjects/BuddyVerse`) — the same ~26 mini-games plus static "connect with friends" content (jokes/riddles/trivia/conversation starters, all built-in, no AI generation of any kind), with local pass-and-play, vs-bot, and real internet multiplayer modes, sharing the same Firebase project as the Android app. This project was scaffolded and the bulk of its games ported by Claude Code directly from the current Android Kotlin source, not written by hand first.

## Commands

```bash
xcodegen generate                          # regenerate BuddyVerse.xcodeproj from project.yml (source of truth — the .xcodeproj itself is gitignored)
xcodebuild -project BuddyVerse.xcodeproj -scheme BuddyVerse -destination 'generic/platform=iOS Simulator' build
open BuddyVerse.xcodeproj                  # open in Xcode for day-to-day iteration
```

**No simulators, ever (owner's rule).** Do not boot, create, download or launch an iOS Simulator, and do not run the app or the UI tests from here. To check that a change compiles, build for a generic device with signing off:

```bash
xcodebuild -project BuddyVerse.xcodeproj -scheme BuddyVerse -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

(The first command above, with `generic/platform=iOS Simulator`, is the old compile-only form; prefer the device form.) After adding a new `.swift` file run `xcodegen generate` first, or the file is not in the project. `.claude/commands/test-app.md` runs the iOS QA agent team in `.claude/agents/` (static review plus that device build) and records results under Known Issues below.

`project.yml` is the source of truth for the Xcode project (target, dependencies, build settings) — edit it, not the generated `.xcodeproj`, and re-run `xcodegen generate` after.

**Deployment target is iOS 14.0** (`project.yml`'s `options.deploymentTarget.iOS` and `targets.BuddyVerse.deploymentTarget`), lowered from an original 17.0 so the app runs on older/hardware-capped devices (e.g. iPads stuck on iOS 15.x that can't upgrade further). This has real, easy-to-reintroduce consequences for anyone touching this codebase — see "iOS 14 compatibility constraints" below before writing new SwiftUI code here.

### One-time setup this project can't do for itself

- **`BuddyVerse/Resources/GoogleService-Info.plist`** — gitignored, and **currently present** on this machine (bundle ID `com.example.buddyverse.ios`, same Firebase project as the Android app, `buddyverse-5fc3e`). On a fresh checkout it has to be re-downloaded from the Firebase console and dropped in this exact path. Without it, `FirebaseApp.configure()` is skipped (guarded in `BuddyVerseApp.swift`) and every multiplayer screen will fail to connect — everything else in the app works fine without it.

## Architecture

Mirrors the Android app's architecture almost 1:1 — see `~/AndroidStudioProjects/BuddyVerse/CLAUDE.md` for the full narrative description of the product/flow; this file only covers what's iOS-specific.

### Navigation

Android chains `AppCompatActivity` screens via `Intent` + extras, with (almost) every screen calling `startActivity()+finish()` so its real back stack stays shallow. This port uses `App/RootView.swift`'s `Router` (`@Published var path: [AppRoute]`) with normal push/pop semantics instead — a deliberate departure, not a literal port: iOS users expect the back button to return to the *immediately previous* screen, not always to Welcome. The one exception is `Router.replaceTop(with:)`, used only for purely automatic no-choice screens (e.g. `AiGeneratingView`) so they don't leave a stray, back-button-hidden stack entry behind.

**`RootView` renders `path` itself in a plain `ZStack`, not a real `NavigationStack`** — `NavigationStack`/`.navigationDestination(for:)` both need iOS 16+, and this app's floor is iOS 14. Every entry in `router.path` stays mounted (indices are stable, since push only appends and pop only drops the last one) so a screen's `@State` survives the player backing into it, and a `.move(edge:)` transition + `.animation()` gives the same push/pop slide `NavigationStack` gives for free. There's deliberately no interactive edge-swipe-to-back gesture (a hand-rolled one risks fighting screens with their own drag gestures, like `WordSearchView`'s selection drag) — every screen already renders its own visible "Back" button calling `router.pop()`, which is the only way back navigation happens here. Don't reach for `NavigationStack`/`.navigationDestination`/`@Environment(\.dismiss)` on a new screen out of habit — use `@EnvironmentObject private var router: Router` and `router.pop()` instead, matching every existing screen.

`AppRoute` (in `App/AppRoute.swift`) enumerates every screen; `GameSelection` is the Swift equivalent of Android's bag of Intent extras (`GAME_TYPE`/`DIFFICULTY`/`IS_BOT`/`IS_NEARBY`/`MOOD`/`AGE_GROUP`/`WORD_MODE`/`PLAYERS`; there is no `AI_ITEMS` anymore, the AI path was removed), passed by value along the navigation path. `GameRouter.gameView(for:)` is the direct equivalent of `InstructionsChoiceActivity.createGameIntent()` — the one place that maps a `GAME_TYPE` string to its game view; add a new game there.

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

### Mandatory first-launch gate, Get Updates, and Admin Dashboard

Both ported from Android features added after this file's initial architecture pass — see `AppFeedbackService`'s doc comments (above) for the Firestore side of all of these.

- **`EnterNameView`/`GetUpdatesView`** (`Navigation/`) — a mandatory, first-launch-only "what's your first name?" gate followed by an optional "get updates" opt-in. Deliberately first-name-only, never an email or full name (not regulated "personal information" under COPPA the way a full name/email is), since this app's Kid content mode means it can genuinely be used by children — see `AppFeedbackService.submitAppUser`/`submitUpdateOptIn`'s doc comments for the fuller reasoning.
- **`RootView`'s gate overlay** — rather than a pushed `AppRoute` (which would need somewhere to pop back *to*), the gate is a plain `ZStack` layer drawn on top of the router's normal content, toggled by a `hasEnteredName` `@State` seeded from `UserDefaults`. This mirrors Android's approach (`EnterNameActivity` started on top of an already-`onCreate()`'d `WelcomeActivity`, never finishing it) using SwiftUI's own idioms instead: `WelcomeView` and the router's content stay mounted underneath the whole time, so finishing the gate just flips a boolean and reveals them — no relaunch, no separate route to manage.
- **Update banner** — `WelcomeView` calls `AppFeedbackService.checkForUpdate` on appear (only if this device opted into Get Updates), which reads the single global `appConfig/latest` Firestore doc and shows a dismissable yellow banner if it names a version *genuinely newer* (a real dotted-version-number comparison, not a `!=` check) than `CFBundleShortVersionString`. `autoPublishUpdateIfNewer` is the write side: called whenever `AuthManager.isAdmin()` is true and `WelcomeView` appears (or the router path empties back out to it), it publishes the currently-running build's own version to that same doc if newer than what's already there — so the version number auto-publishes itself the moment the admin opens a freshly-installed build, without ever needing to hand-type it into the Admin Dashboard. The two must use the *same* "newer than" comparison, or the admin's own device can flash a nonsensical "downgrade" banner in the instant before its own auto-publish write lands.
- **`AdminDashboardView`** — reachable only via the "🛠️ Admin Dashboard" footer link on `WelcomeView`, itself only visible when `AuthManager.isAdmin()` (checked on appear and whenever the router path empties back to Welcome, so logging in/out is reflected without a relaunch). Shows play counts, feedback, reports, the Updates publish form (version/message fields + subscriber list) and app-user (name-gate) records, all mirroring Android's sections — deliberately **no revenue/purchase log** on iOS to match Android's dropped section (see the platform-divergence note above: Android's paywall being off made that section meaningless there; it was removed on both platforms for parity even though iOS's own paywall is still technically live). Deletion exists only for feedback/report rows, each behind a confirmation `Alert` — Play Counts, app users, and Get Updates subscribers are intentionally read-only (matches Android exactly; a delete-with-confirmation pass was added to all three and then explicitly reverted per product decision, keep it that way unless told otherwise). **History note:** the Updates form and App Users list were first ported to `AppFeedbackService` only, with no actual UI in `AdminDashboardView` for a while — don't assume a function existing in `AppFeedbackService` means its screen was ever built; check the view file too.

### Conventions

Comments follow the Android project's established style: plain-English explanations of *why*, not terse dev-shorthand — match this when touching existing files.

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
- **Status (2026-10-15):** **Left for the owner.** The file is not referenced by any code, not bundled and not committed, but it holds a live-looking key. Only the owner can revoke the key in the Google console; deleting the local file is also left to the owner because it cannot be undone.

#### ISSUE-12: Admin dashboard shows a leftover 'TEST' pill and has a stale comment
- **Severity:** LOW
- **Area:** content
- **File:** Navigation/AdminDashboardView.swift:379-386, 25-26
- **Found by:** qa-content (2026-10-15)
- **Description:** testBuildMarker is a debug leftover; a comment says play counts have delete actions but they are read-only.
- **Suggested fix:** Remove the marker and fix the comment.
- **Status (2026-10-15):** **Partly fixed.** The stale comment was corrected. The 'TEST' pill was left in place on purpose: its own comment says it is a deliberate marker for confirming a fresh build is running, so removing it is the owner's call.

### Fixed

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
