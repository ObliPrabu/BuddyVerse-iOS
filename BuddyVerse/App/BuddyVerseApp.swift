import SwiftUI
import FirebaseCore

// Mirrors the Android BuddyVerseApp Application subclass: applies the saved
// theme before the first screen appears (no flash-of-wrong-theme) and drives
// MusicManager off foreground/background transitions. Firebase only
// configures if a real GoogleService-Info.plist is present in Resources/ - see
// CLAUDE.md for the one-time setup step this project can't do for itself (the
// file has to come from the Firebase console).
@main
struct BuddyVerseApp: App {
    @StateObject private var theme = ThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        MusicManager.shared.start()
        // Touching .shared this early sets UNUserNotificationCenter's
        // delegate before AdminDashboardView could ever publish a version
        // and fire a notification off of it.
        _ = LocalNotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(theme.colorScheme)
                .onOpenURL { url in
                    // Currently only the BuddyVerseWidget home-screen widget
                    // sends one of these (buddyverse://daily/...) - see
                    // DeepLinkManager.swift.
                    DeepLinkManager.shared.handle(url)
                }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                MusicManager.shared.onAppForegrounded()
                LiveActivityManager.end()
                AdminFeedbackChecker.checkNow()
            case .background:
                MusicManager.shared.onAppBackgrounded()
                LiveActivityManager.start()
            default: break
            }
        }
    }
}
