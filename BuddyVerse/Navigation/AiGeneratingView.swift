import SwiftUI

/// Mirrors AiGeneratingActivity/activity_ai_generating.xml: the "Using AI to
/// make good jokes for you..." screen - same welcome_gradient background, a
/// large white spinner, and the exact bold-white message + teal "Just a
/// moment!" subtext. Calls Gemini in the background, then continues on with
/// whatever it got back (or nil, so the game screen falls back to built-in
/// content).
struct AiGeneratingView: View {
    let gameType: String
    let mood: String
    let ageGroup: String
    let difficulty: String
    @EnvironmentObject private var router: Router
    @State private var isCancelled = false

    // AiContentService.generate() never actually calls Gemini for KID or
    // JOKES (see its own doc comment) - showing "Using AI..." on this screen
    // for those cases would be actively false, not just misleading, so this
    // screen's own wording has to match what's really about to happen.
    private var loadingMessage: String {
        if ageGroup == "KID" || gameType == "JOKES" {
            return "Getting your \(AiContentService.categoryName(for: gameType)) ready..."
        }
        return "Using AI to make good \(AiContentService.categoryName(for: gameType)) for you..."
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .accentColor(.white)
                    .scaleEffect(2.2)
                    .frame(width: 70, height: 70)
                    .padding(.bottom, 30)

                Text(loadingMessage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("Just a moment!")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: 0xE0F7FA))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .onAppear {
            // `.task {}` needs iOS 15 - `.onAppear` + a manually-started
            // `Task` gets the same "kick off async work when this screen
            // appears" behavior back to iOS 14 (the async/await runtime
            // itself back-deploys fine).
            Task {
                let items = await AiContentService.generate(gameType: gameType, mood: mood, ageGroup: ageGroup, difficulty: difficulty)
                // Guard against the user having already backed out while the
                // (up to 12s) network call was still in flight.
                if !isCancelled {
                    var selection = GameSelection(gameType: gameType, difficulty: difficulty, isBot: false)
                    selection.mood = mood
                    selection.ageGroup = ageGroup
                    selection.aiItems = (items?.isEmpty == false) ? items : nil
                    router.replaceTop(with: .instructionsChoice(selection))
                }
            }
        }
        .onDisappear { isCancelled = true }
    }
}
