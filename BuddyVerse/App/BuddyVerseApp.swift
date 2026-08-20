import SwiftUI
import FirebaseCore

// Mirrors the Android BuddyVerseApp Application subclass: applies the saved
// theme before the first screen appears (no flash-of-wrong-theme) and drives
// MusicManager off foreground/background transitions. Firebase only
// configures if a real GoogleService-Info.plist has been dropped in - see
// Resources/Secrets.example.plist and CLAUDE.md for the one-time setup step
// this project can't do for itself (it has to come from the Firebase console).
@main
struct BuddyVerseApp: App {
    @StateObject private var theme = ThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        MusicManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(theme.colorScheme)
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active: MusicManager.shared.onAppForegrounded()
            case .background: MusicManager.shared.onAppBackgrounded()
            default: break
            }
        }
    }
}
