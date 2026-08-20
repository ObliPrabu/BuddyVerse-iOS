import SwiftUI
import Combine

// Mirrors ThemePrefs.kt: light/dark/system-follow, persisted so the choice
// survives a relaunch. `colorScheme == nil` is the SwiftUI equivalent of
// Android's MODE_NIGHT_FOLLOW_SYSTEM - it tells the WindowGroup to defer to
// the OS setting instead of forcing one.
final class ThemeManager: ObservableObject {
    // Only ever created/used on the main thread (SwiftUI view code), same as
    // every other cross-cutting singleton in this app - see MusicManager and
    // InternetConnectionManager for the same pattern.
    nonisolated(unsafe) static let shared = ThemeManager()

    enum Mode: Int {
        case system = 0
        case light = 1
        case dark = 2
    }

    private let defaultsKey = "buddyverse_theme_mode"

    @Published private(set) var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey) }
    }

    private init() {
        let saved = UserDefaults.standard.integer(forKey: defaultsKey)
        mode = Mode(rawValue: saved) ?? .system
    }

    var colorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Switches between Light and Dark (used by the toggle button), matching
    /// ThemePrefs.toggle()'s behavior of never landing back on "system" from a tap.
    func toggle() {
        mode = (mode == .dark) ? .light : .dark
    }

    /// True if dark is currently showing, resolving "system" against the
    /// device's actual current appearance.
    func isDarkActive(systemScheme: ColorScheme) -> Bool {
        switch mode {
        case .dark: return true
        case .light: return false
        case .system: return systemScheme == .dark
        }
    }
}
