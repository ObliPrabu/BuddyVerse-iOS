import Foundation
import FirebaseFirestore

/// Play-count tracking, free-text feedback, and content/bug reports - all
/// self-reported, all written straight to Firestore with no auth requirement
/// (most single-player game launches never establish any auth session at
/// all), and all readable only by the one admin account via the in-app
/// Admin Dashboard.
enum AppFeedbackService {
    private static var db: Firestore { Firestore.firestore() }

    /// Called exactly once per game launch, from the single choke point
    /// every game route funnels through (RootView's `.game` case) - never
    /// call this from an individual game screen directly, or a re-render
    /// could double-count.
    static func incrementPlayCount(gameType: String) {
        db.collection("playCounts").document(gameType)
            .setData(["count": FieldValue.increment(Int64(1))], merge: true)
    }

    static func submitFeedback(gameType: String, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        db.collection("feedback").addDocument(data: [
            "gameType": gameType,
            "message": trimmed,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    static func submitReport(gameType: String, reason: String, detail: String) {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        db.collection("reports").addDocument(data: [
            "gameType": gameType,
            "reason": reason,
            "detail": trimmedDetail,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    /// Human-readable name for a GAME_TYPE constant, used by the Feedback/
    /// Report sheets and the Admin Dashboard's play-count list - mirrors the
    /// display names already used across Welcome/game screens.
    static func displayName(for gameType: String) -> String {
        switch gameType {
        case "JOKES": return "Jokes"
        case "RIDDLES": return "Riddles"
        case "TRIVIA": return "Trivia"
        case "CONVERSATION": return "Conversation Starters"
        case "TICTACTOE": return "Tic-Tac-Toe"
        case "RPS": return "Rock Paper Scissors"
        case "SUDOKU": return "Sudoku"
        case "MAZE": return "Amazing Maze"
        case "COUNT21": return "Count to 21"
        case "WORDSEARCH": return "Word Search"
        case "MEMORY": return "Memory Match"
        case "SEQUENCE": return "Memory Sequence"
        case "SLIDE": return "Slide Puzzle"
        case "HANGMAN": return "Hangman"
        case "MATH": return "Math Sprint"
        case "SPACE": return "Space Explorer"
        case "JUNGLE": return "Jungle Run"
        case "OCEAN": return "Ocean Dive"
        case "MOUNTAIN": return "Mountain Climb"
        case "DESERT": return "Desert Trek"
        case "VOLCANO": return "Volcano Climb"
        case "ARCTIC": return "Arctic Trek"
        case "SAVANNA": return "Savanna Safari"
        case "CAVE": return "Cave Explorer"
        case "SWAMP": return "Swamp Trek"
        case "STORM": return "Storm Chase"
        default: return gameType
        }
    }

    static let reportReasons = [
        "Bug or glitch",
        "Game froze or crashed",
        "Confusing instructions",
        "Inappropriate content",
        "Other"
    ]

    /// The mandatory first-launch name gate (EnterNameView) - first name
    /// only, never an email or full name, so this stays safe to require from
    /// every player even though the app's Kid content mode means some of
    /// them really are children (a first name alone isn't regulated
    /// "personal information" under COPPA the way a full name or email is).
    static func submitAppUser(firstName: String) {
        db.collection("appUsers").addDocument(data: [
            "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "joinedAt": FieldValue.serverTimestamp()
        ])
    }

    /// A deliberately minimal "get updates" opt-in - first name only, no
    /// email/password collected at all. Update delivery itself never leaves
    /// the app: see checkForUpdate() below, which just compares
    /// appConfig/latest against the installed version and shows an in-app
    /// banner - there is no outbound email sending anywhere in this flow.
    static func submitUpdateOptIn(firstName: String) {
        db.collection("updatesOptIn").addDocument(data: [
            "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "optedInAt": FieldValue.serverTimestamp()
        ])
    }

    /// Reads the single global appConfig/latest doc the admin publishes from
    /// the Admin Dashboard (or autoPublishUpdateIfNewer), and compares its
    /// versionName against the currently-running build (CFBundleShortVersionString,
    /// set by MARKETING_VERSION in project.yml) using a real semantic-version
    /// comparison - not just "differs from", which would wrongly show an
    /// "update available" banner for a device that's already AHEAD of
    /// what's published (e.g. the admin's own device, in the brief window
    /// before autoPublishUpdateIfNewer's write lands). Calls back with
    /// (message, versionName) only if the published version is genuinely
    /// newer, or nil if not/the read fails - failing silent on error is
    /// intentional, since this is a non-critical convenience feature that
    /// should never be able to crash or block app startup.
    static func checkForUpdate(onResult: @escaping @MainActor ((message: String, versionName: String)?) -> Void) {
        db.collection("appConfig").document("latest").getDocument { doc, error in
            guard error == nil, let doc, doc.exists else {
                runOnMain { onResult(nil) }
                return
            }
            let latestVersion = doc.get("versionName") as? String
            let message = doc.get("message") as? String ?? ""
            let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            if let latestVersion, let installedVersion, isVersionNewer(latestVersion, installedVersion) {
                runOnMain { onResult((message: message, versionName: latestVersion)) }
            } else {
                runOnMain { onResult(nil) }
            }
        }
    }

    /// Auto-publishes the currently-installed version to appConfig/latest the
    /// first time the admin account opens a newly-installed build - removes
    /// the need to manually type the version into the Admin Dashboard's
    /// Updates section every release (see WelcomeView, the only caller).
    /// Only fires when the installed version is genuinely NEWER than what's
    /// already published (a real semantic-version comparison, not just
    /// "different from" - so reinstalling an older build for testing can
    /// never downgrade what real users see), and only ever touches the
    /// versionName field - a "what's new" message published afterward from
    /// Android's Admin Dashboard is left untouched, since this never
    /// re-fires again until the next real version bump.
    static func autoPublishUpdateIfNewer() {
        guard let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        let appConfigDoc = db.collection("appConfig").document("latest")
        appConfigDoc.getDocument { doc, _ in
            let publishedVersion = doc?.get("versionName") as? String
            if publishedVersion == nil || isVersionNewer(installedVersion, publishedVersion!) {
                appConfigDoc.setData([
                    "versionName": installedVersion,
                    "message": "",
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            }
        }
    }

    /// True only if `a` is a strictly newer dotted version number than `b` (e.g. "1.5.10" > "1.5.9").
    private static func isVersionNewer(_ a: String, _ b: String) -> Bool {
        let partsA = a.split(separator: ".").map { Int($0) ?? 0 }
        let partsB = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(partsA.count, partsB.count) {
            let pa = i < partsA.count ? partsA[i] : 0
            let pb = i < partsB.count ? partsB[i] : 0
            if pa != pb { return pa > pb }
        }
        return false
    }
}
