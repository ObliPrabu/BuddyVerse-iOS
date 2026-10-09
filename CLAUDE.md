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

`project.yml` is the source of truth for the Xcode project (target, dependencies, build settings) — edit it, not the generated `.xcodeproj`, and re-run `xcodegen generate` after.

**Deployment target is iOS 14.0** (`project.yml`'s `options.deploymentTarget.iOS` and `targets.BuddyVerse.deploymentTarget`), lowered from an original 17.0 so the app runs on older/hardware-capped devices (e.g. iPads stuck on iOS 15.x that can't upgrade further). This has real, easy-to-reintroduce consequences for anyone touching this codebase — see "iOS 14 compatibility constraints" below before writing new SwiftUI code here.

### One-time setup this project can't do for itself

- **`BuddyVerse/Resources/GoogleService-Info.plist`** — gitignored, **not yet added**. Register an iOS app with bundle ID `com.example.buddyverse.ios` under the same Firebase project as the Android app (`buddyverse-5fc3e`) in the Firebase console, download its `GoogleService-Info.plist`, and drop it in this exact path. Without it, `FirebaseApp.configure()` is skipped (guarded in `BuddyVerseApp.swift`) and every multiplayer screen will fail to connect — everything else in the app works fine without it.

## Architecture

Mirrors the Android app's architecture almost 1:1 — see `~/AndroidStudioProjects/BuddyVerse/CLAUDE.md` for the full narrative description of the product/flow; this file only covers what's iOS-specific.

### Navigation

Android chains `AppCompatActivity` screens via `Intent` + extras, with (almost) every screen calling `startActivity()+finish()` so its real back stack stays shallow. This port uses `App/RootView.swift`'s `Router` (`@Published var path: [AppRoute]`) with normal push/pop semantics instead — a deliberate departure, not a literal port: iOS users expect the back button to return to the *immediately previous* screen, not always to Welcome. The one exception is `Router.replaceTop(with:)`, used only for purely automatic no-choice screens (e.g. `AiGeneratingView`) so they don't leave a stray, back-button-hidden stack entry behind.

**`RootView` renders `path` itself in a plain `ZStack`, not a real `NavigationStack`** — `NavigationStack`/`.navigationDestination(for:)` both need iOS 16+, and this app's floor is iOS 14. Every entry in `router.path` stays mounted (indices are stable, since push only appends and pop only drops the last one) so a screen's `@State` survives the player backing into it, and a `.move(edge:)` transition + `.animation()` gives the same push/pop slide `NavigationStack` gives for free. There's deliberately no interactive edge-swipe-to-back gesture (a hand-rolled one risks fighting screens with their own drag gestures, like `WordSearchView`'s selection drag) — every screen already renders its own visible "Back" button calling `router.pop()`, which is the only way back navigation happens here. Don't reach for `NavigationStack`/`.navigationDestination`/`@Environment(\.dismiss)` on a new screen out of habit — use `@EnvironmentObject private var router: Router` and `router.pop()` instead, matching every existing screen.

`AppRoute` (in `App/AppRoute.swift`) enumerates every screen; `GameSelection` is the Swift equivalent of Android's bag of Intent extras (`GAME_TYPE`/`DIFFICULTY`/`IS_BOT`/`IS_NEARBY`/`MOOD`/`AGE_GROUP`/`AI_ITEMS`/`WORD_MODE`), passed by value along the navigation path. `GameRouter.gameView(for:)` is the direct equivalent of `InstructionsChoiceActivity.createGameIntent()` — the one place that maps a `GAME_TYPE` string to its game view; add a new game there.

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

- `InternetConnectionManager` — a from-scratch Swift port of the Android object of the same name, using `FirebaseFirestore`/`FirebaseAuth` directly (closure-based API, not async/await, to stay a close structural match to the Kotlin callback style). Same room-code/anonymous-auth/transactional-join/message-buffering/word-mode-sync design as Android; keep the two in sync if the wire protocol changes on either side, since they talk to the same Firestore project.
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
