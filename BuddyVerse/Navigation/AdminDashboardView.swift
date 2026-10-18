import SwiftUI
import FirebaseFirestore

/// The screen WelcomeView's "🛠️ Admin Dashboard" link opens - only ever
/// reachable while signed in as the one designated admin account
/// (AuthManager.isAdmin()). Purely operational stats (play counts, feedback/
/// reports) - there is no payment system in the app.
struct AdminDashboardView: View {
    @EnvironmentObject private var router: Router

    @State private var playCounts: [(gameType: String, count: Int)] = []
    @State private var feedbackItems: [FeedbackItem] = []
    @State private var reportItems: [ReportItem] = []
    @State private var activeAlert: AdminAlert?

    @State private var latestVersionInput = ""
    @State private var updateMessageInput = ""
    @State private var currentlyPublishedText = "Loading current update notice..."
    @State private var updateSubscribersCountText = "Loading subscribers..."
    @State private var updateSubscribers: [String] = []
    @State private var appUsersCountText = "Loading app users..."
    @State private var appUsersList: [String] = []

    // Every delete action on this whole screen (feedback and reports only -
    // play counts, app users and Get Updates subscribers are read-only)
    // routes through here first - nothing gets removed from
    // Firestore without the admin confirming, since there's no undo once a
    // doc is gone. Both alert kinds share one `.alert(item:)` (rather than
    // two separate `.alert(isPresented:)` modifiers) since SwiftUI only
    // reliably presents one active alert per view.
    private enum AdminAlert: Identifiable {
        case confirmDelete(message: String, action: () -> Void)
        case deleteFailed(String)
        case confirmSignOut
        case info(title: String, message: String)

        var id: String {
            switch self {
            case .confirmDelete(let message, _): return "confirm:\(message)"
            case .deleteFailed(let message): return "failed:\(message)"
            case .confirmSignOut: return "confirmSignOut"
            case .info(let title, let message): return "info:\(title):\(message)"
            }
        }
    }

    private struct FeedbackItem: Identifiable {
        let id: String
        let gameType: String
        let message: String
        let isNew: Bool
    }

    private struct ReportItem: Identifiable {
        let id: String
        let gameType: String
        let reason: String
        let detail: String
        let isNew: Bool
    }

    // Captured once in .onAppear, before AdminNotificationTracker.markViewedNow()
    // moves the stored value to "now" - this visit's rows still need the OLD
    // last-viewed time to know what's new-to-them.
    @State private var previousLastViewed: Timestamp?

    private let baseBg = Color(hex: 0x1A237E)

    var body: some View {
        ZStack {
            baseBg.ignoresSafeArea()

            content

            VStack {
                HStack(spacing: 10) {
                    backButton
                    homeButton
                    signOutButton
                    Spacer()
                    testBuildMarker
                }
                Spacer()
            }
            .padding(16)
        }
        .onAppear {
            // Defence in depth: the Welcome footer link is the only way here
            // and only shows for the admin, but this screen reads
            // admin-only data, so it checks for itself too instead of
            // trusting how it was reached.
            guard AuthManager.isAdmin() else {
                router.pop()
                return
            }
            previousLastViewed = AdminNotificationTracker.lastViewedAt()
            AdminNotificationTracker.markViewedNow()
            loadPlayCounts()
            loadFeedback()
            loadReports()
            loadCurrentlyPublished()
            loadUpdateSubscribers()
            loadAppUsers()
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmDelete(let message, let action):
                return Alert(
                    title: Text("Delete?"),
                    message: Text(message),
                    primaryButton: .destructive(Text("Delete"), action: action),
                    secondaryButton: .cancel()
                )
            case .deleteFailed(let message):
                return Alert(title: Text("Delete Failed"), message: Text(message), dismissButton: .default(Text("OK")))
            case .confirmSignOut:
                return Alert(
                    title: Text("Sign Out?"),
                    message: Text("Are you sure you want to sign out?"),
                    primaryButton: .destructive(Text("Sign Out")) {
                        AuthManager.logOut()
                        router.popToRoot()
                    },
                    secondaryButton: .cancel()
                )
            case .info(let title, let message):
                return Alert(title: Text(title), message: Text(message), dismissButton: .default(Text("OK")))
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("📊 Admin Dashboard")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 60)
                    .padding(.bottom, 30)

                sectionHeader("🎮 Play Counts")
                if playCounts.isEmpty {
                    emptyRow("No plays logged yet.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(playCounts, id: \.gameType) { entry in
                            HStack {
                                Text(AppFeedbackService.displayName(for: entry.gameType))
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(entry.count)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.2)))
                        }
                    }
                    .padding(.horizontal, 24)
                }

                sectionHeader("💬 Feedback (\(feedbackItems.count) recent)")
                if feedbackItems.isEmpty {
                    emptyRow("No feedback submitted yet.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(feedbackItems) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.isNew ? "🔴 NEW · \(AppFeedbackService.displayName(for: item.gameType))" : AppFeedbackService.displayName(for: item.gameType))
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Color.white.opacity(0.6))
                                    Text(item.message)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                deleteButton {
                                    activeAlert = .confirmDelete(message: "Delete this feedback? This can't be undone.") {
                                        deleteFeedback(id: item.id)
                                    }
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(item.isNew ? Color(hex: 0xFF8A80).opacity(0.25) : Color.black.opacity(0.2)))
                        }
                    }
                    .padding(.horizontal, 24)
                }

                sectionHeader("🚩 Reports (\(reportItems.count) recent)")
                if reportItems.isEmpty {
                    emptyRow("No reports submitted yet.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(reportItems) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.isNew ? "🔴 NEW · \(AppFeedbackService.displayName(for: item.gameType))" : AppFeedbackService.displayName(for: item.gameType))
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color.white.opacity(0.6))
                                        Spacer()
                                        Text(item.reason)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color(hex: 0xFF8A80))
                                    }
                                    if !item.detail.isEmpty {
                                        Text(item.detail)
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                    }
                                }
                                deleteButton {
                                    activeAlert = .confirmDelete(message: "Delete this report? This can't be undone.") {
                                        deleteReport(id: item.id)
                                    }
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(item.isNew ? Color(hex: 0xFF8A80).opacity(0.25) : Color.black.opacity(0.2)))
                        }
                    }
                    .padding(.horizontal, 24)
                }

                sectionHeader("📢 Updates")
                VStack(spacing: 14) {
                    placeholderField(placeholder: "Latest Version (e.g. 1.4.8)", text: $latestVersionInput) {
                        TextField("", text: $latestVersionInput)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    placeholderField(placeholder: "What's new?", text: $updateMessageInput) {
                        TextField("", text: $updateMessageInput)
                            .foregroundColor(.white)
                    }
                    Button(action: publishUpdate) {
                        Text("Publish Update Notice")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(hex: 0x4CAF50))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    Text(currentlyPublishedText)
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.2)))
                .padding(.horizontal, 24)

                Text(updateSubscribersCountText)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                if updateSubscribers.isEmpty {
                    emptyRow("No one has opted in yet.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(updateSubscribers.enumerated()), id: \.offset) { _, name in
                            statRow(name)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                sectionHeader("👋 App Users")
                Text(appUsersCountText)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                if appUsersList.isEmpty {
                    emptyRow("No one has entered a name yet.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(appUsersList.enumerated()), id: \.offset) { _, name in
                            statRow(name)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// `TextField`'s `prompt:` initializer needs iOS 15 - this is the
    /// pre-15 way to get the same placeholder text: layer it under the
    /// field by hand and only show it while empty.
    private func placeholderField<Content: View>(
        placeholder: String,
        text: Binding<String>,
        @ViewBuilder field: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundColor(Color.white.opacity(0.4))
            }
            field()
        }
        .padding(.vertical, 8)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.3)), alignment: .bottom)
    }

    private func statRow(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 14))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.2)))
    }

    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("✕")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(6)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 12)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(Color.white.opacity(0.5))
            .padding(.horizontal, 24)
    }

    private var backButton: some View {
        Button("Back") { router.pop() }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(baseBg)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
            .buttonStyle(.plain)
    }

    private var homeButton: some View {
        Button("Home") { router.popToRoot() }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(baseBg)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
            .buttonStyle(.plain)
    }

    // This screen is only ever reachable while signed in, so signing out
    // and popping all the way back to Welcome (like homeButton) is the only
    // sensible place to land afterward.
    // Deliberately not a version bump - a quick visible marker to confirm a
    // freshly-installed build is actually running the latest source, since
    // MARKETING_VERSION itself doesn't change for every internal test build.
    private var testBuildMarker: some View {
        Text("TEST")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.2))
    }

    private var signOutButton: some View {
        Button("Sign Out") { activeAlert = .confirmSignOut }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color(hex: 0xC62828))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
            .buttonStyle(.plain)
    }

    private func loadPlayCounts() {
        Firestore.firestore().collection("playCounts").getDocuments { snapshot, _ in
            let entries: [(gameType: String, count: Int)] = (snapshot?.documents ?? []).map { doc in
                (gameType: doc.documentID, count: doc.get("count") as? Int ?? 0)
            }
            runOnMain { playCounts = entries.sorted { $0.count > $1.count } }
        }
    }

    private func isNewSince(_ createdAt: Timestamp?) -> Bool {
        guard let createdAt, let previousLastViewed else { return false }
        return createdAt.dateValue() > previousLastViewed.dateValue()
    }

    private func loadFeedback() {
        Firestore.firestore().collection("feedback")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, _ in
                // Pull the plain values out of the Firestore documents here,
                // then hand only those to the main actor - the snapshot
                // itself isn't safe to pass between threads.
                let rows = (snapshot?.documents ?? []).map { doc in
                    (
                        id: doc.documentID,
                        createdAt: doc.get("createdAt") as? Timestamp,
                        gameType: doc.get("gameType") as? String ?? "",
                        message: doc.get("message") as? String ?? ""
                    )
                }
                runOnMain {
                    feedbackItems = rows.map {
                        FeedbackItem(id: $0.id, gameType: $0.gameType, message: $0.message, isNew: isNewSince($0.createdAt))
                    }
                }
            }
    }

    private func loadReports() {
        Firestore.firestore().collection("reports")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, _ in
                let rows = (snapshot?.documents ?? []).map { doc in
                    (
                        id: doc.documentID,
                        createdAt: doc.get("createdAt") as? Timestamp,
                        gameType: doc.get("gameType") as? String ?? "",
                        reason: doc.get("reason") as? String ?? "",
                        detail: doc.get("detail") as? String ?? ""
                    )
                }
                runOnMain {
                    reportItems = rows.map {
                        ReportItem(id: $0.id, gameType: $0.gameType, reason: $0.reason, detail: $0.detail, isNew: isNewSince($0.createdAt))
                    }
                }
            }
    }

    private nonisolated func displayFirstName(_ doc: QueryDocumentSnapshot) -> String {
        let name = (doc.get("firstName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false) ? name! : "(no name given)"
    }

    private func loadCurrentlyPublished() {
        Firestore.firestore().collection("appConfig").document("latest").getDocument { doc, error in
            guard error == nil else {
                runOnMain { currentlyPublishedText = "Couldn't load current update notice." }
                return
            }
            guard let doc, doc.exists, let version = doc.get("versionName") as? String else {
                runOnMain { currentlyPublishedText = "Nothing published yet." }
                return
            }
            let message = doc.get("message") as? String ?? ""
            runOnMain { currentlyPublishedText = message.isEmpty ? "Currently live: v\(version)" : "Currently live: v\(version) — \(message)" }
        }
    }

    private func publishUpdate() {
        let version = latestVersionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = updateMessageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            activeAlert = .info(title: "Missing Version", message: "Enter a version number first.")
            return
        }
        Firestore.firestore().collection("appConfig").document("latest").setData([
            "versionName": version,
            "message": message,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            let succeeded = error == nil
            runOnMain {
                if succeeded {
                    activeAlert = .info(title: "Published", message: "Update notice published!")
                    loadCurrentlyPublished()
                    LocalNotificationManager.shared.notifyVersionPublished(version: version, message: message)
                } else {
                    activeAlert = .info(title: "Publish Failed", message: "Couldn't publish - try again.")
                }
            }
        }
    }

    private func loadUpdateSubscribers() {
        Firestore.firestore().collection("updatesOptIn")
            .order(by: "optedInAt", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, _ in
                let docs = snapshot?.documents ?? []
                let names = docs.map { displayFirstName($0) }
                runOnMain {
                    updateSubscribersCountText = "\(names.count >= 50 ? "50+" : "\(names.count)") subscriber\(names.count == 1 ? "" : "s") (most recent 50 shown below)"
                    updateSubscribers = names
                }
            }
    }

    private func loadAppUsers() {
        Firestore.firestore().collection("appUsers")
            .order(by: "joinedAt", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, _ in
                let docs = snapshot?.documents ?? []
                let names = docs.map { displayFirstName($0) }
                runOnMain {
                    appUsersCountText = "\(names.count >= 50 ? "50+" : "\(names.count)") app user\(names.count == 1 ? "" : "s") (most recent 50 shown below)"
                    appUsersList = names
                }
            }
    }

    private func deleteFeedback(id: String) {
        Firestore.firestore().collection("feedback").document(id).delete { error in
            let succeeded = error == nil
            runOnMain {
                if succeeded {
                    feedbackItems.removeAll { $0.id == id }
                } else {
                    activeAlert = .deleteFailed("Couldn't delete - try again.")
                }
            }
        }
    }

    private func deleteReport(id: String) {
        Firestore.firestore().collection("reports").document(id).delete { error in
            let succeeded = error == nil
            runOnMain {
                if succeeded {
                    reportItems.removeAll { $0.id == id }
                } else {
                    activeAlert = .deleteFailed("Couldn't delete - try again.")
                }
            }
        }
    }
}
