import SwiftUI
import FirebaseFirestore

/// The screen WelcomeView's "📊 Admin" pill opens - only ever reachable
/// while signed in as the one designated admin account (AuthManager.isAdmin()).
/// Sums SubscriptionManager's `purchases` log entirely in-app - no browser,
/// no Stripe Dashboard link. See SubscriptionManager.logPurchase's doc
/// comment for the important caveat this screen inherits: these numbers are
/// a self-reported log of successful checkouts as the app itself observed
/// them, not Stripe's own authoritative ledger (no refunds/chargebacks
/// reflected, since there's no backend here to receive Stripe webhooks).
/// Also shows AppFeedbackService's play counts, feedback, and reports -
/// all in-app, same self-reported/no-backend caveat applies to those too.
struct AdminDashboardView: View {
    @EnvironmentObject private var router: Router

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var totals: [String: (count: Int, cents: Int)] = [:]
    @State private var totalCents = 0
    @State private var totalCount = 0

    @State private var playCounts: [(gameType: String, count: Int)] = []
    @State private var feedbackItems: [FeedbackItem] = []
    @State private var reportItems: [ReportItem] = []

    private struct FeedbackItem: Identifiable {
        let id: String
        let gameType: String
        let message: String
    }

    private struct ReportItem: Identifiable {
        let id: String
        let gameType: String
        let reason: String
        let detail: String
    }

    private let baseBg = Color(hex: 0x1A237E)

    var body: some View {
        ZStack {
            baseBg.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .accentColor(.white)
                    .scaleEffect(1.6)
            } else {
                content
            }

            VStack {
                HStack {
                    backButton
                    Spacer()
                }
                Spacer()
            }
            .padding(16)
        }
        .navigationBarHidden(true)
        .onAppear {
            load()
            loadPlayCounts()
            loadFeedback()
            loadReports()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("📊 Admin Dashboard")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 60)
                    .padding(.bottom, 4)

                Text("Self-reported from this app - not Stripe's own ledger")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0xFF8A80))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    Text("$\(formatDollars(totalCents))")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(totalCount) purchase\(totalCount == 1 ? "" : "s") total")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(.bottom, 30)

                    VStack(spacing: 12) {
                        breakdownRow(label: "$4/month subscriptions", key: "monthly")
                        breakdownRow(label: "$40/year subscriptions", key: "yearly")
                        breakdownRow(label: "50¢ expedition unlocks", key: "expedition")
                    }
                    .padding(.horizontal, 24)
                }

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
                                    Text(AppFeedbackService.displayName(for: item.gameType))
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Color.white.opacity(0.6))
                                    Text(item.message)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                deleteButton { deleteFeedback(id: item.id) }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.2)))
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
                                        Text(AppFeedbackService.displayName(for: item.gameType))
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
                                deleteButton { deleteReport(id: item.id) }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.2)))
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
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

    private func breakdownRow(label: String, key: String) -> some View {
        let entry = totals[key] ?? (count: 0, cents: 0)
        return HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.white)
            Spacer()
            Text("\(entry.count)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color.white.opacity(0.7))
            Text("$\(formatDollars(entry.cents))")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
    }

    private func formatDollars(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
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

    private func load() {
        Firestore.firestore().collection("purchases").getDocuments { snapshot, error in
            isLoading = false
            if let error {
                errorMessage = "Couldn't load purchase log: \(error.localizedDescription)"
                return
            }
            var byPlan: [String: (count: Int, cents: Int)] = [:]
            var sumCents = 0
            var count = 0
            for doc in snapshot?.documents ?? [] {
                let plan = doc.get("plan") as? String ?? "unknown"
                let cents = doc.get("amountCents") as? Int ?? 0
                let existing = byPlan[plan] ?? (count: 0, cents: 0)
                byPlan[plan] = (count: existing.count + 1, cents: existing.cents + cents)
                sumCents += cents
                count += 1
            }
            totals = byPlan
            totalCents = sumCents
            totalCount = count
        }
    }

    private func loadPlayCounts() {
        Firestore.firestore().collection("playCounts").getDocuments { snapshot, _ in
            let entries: [(gameType: String, count: Int)] = (snapshot?.documents ?? []).map { doc in
                (gameType: doc.documentID, count: doc.get("count") as? Int ?? 0)
            }
            playCounts = entries.sorted { $0.count > $1.count }
        }
    }

    private func loadFeedback() {
        Firestore.firestore().collection("feedback")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, _ in
                feedbackItems = (snapshot?.documents ?? []).map { doc in
                    FeedbackItem(
                        id: doc.documentID,
                        gameType: doc.get("gameType") as? String ?? "",
                        message: doc.get("message") as? String ?? ""
                    )
                }
            }
    }

    private func loadReports() {
        Firestore.firestore().collection("reports")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, _ in
                reportItems = (snapshot?.documents ?? []).map { doc in
                    ReportItem(
                        id: doc.documentID,
                        gameType: doc.get("gameType") as? String ?? "",
                        reason: doc.get("reason") as? String ?? "",
                        detail: doc.get("detail") as? String ?? ""
                    )
                }
            }
    }

    private func deleteFeedback(id: String) {
        feedbackItems.removeAll { $0.id == id }
        Firestore.firestore().collection("feedback").document(id).delete()
    }

    private func deleteReport(id: String) {
        reportItems.removeAll { $0.id == id }
        Firestore.firestore().collection("reports").document(id).delete()
    }
}
