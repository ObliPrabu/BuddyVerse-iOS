import SwiftUI

/// Mirrors AiGeneratingActivity/activity_ai_generating.xml: same
/// welcome_gradient background, large white spinner, and bold-white message
/// + teal "Just a moment!" subtext as before. Content generation is always
/// the app's own built-in static pool now - there's no AI call of any kind
/// here anymore, for any game type or age group.
struct AiGeneratingView: View {
    let gameType: String
    let mood: String
    let ageGroup: String
    let difficulty: String
    @EnvironmentObject private var router: Router
    @State private var isCancelled = false

    private var loadingMessage: String {
        "Getting your \(AiContentService.categoryName(for: gameType)) ready..."
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
                try? await Task.sleep(nanoseconds: 600_000_000)
                if !isCancelled {
                    var selection = GameSelection(gameType: gameType, difficulty: difficulty, isBot: false)
                    selection.mood = mood
                    selection.ageGroup = ageGroup
                    selection.aiItems = nil
                    router.replaceTop(with: .instructionsChoice(selection))
                }
            }
        }
        .onDisappear { isCancelled = true }
    }
}
