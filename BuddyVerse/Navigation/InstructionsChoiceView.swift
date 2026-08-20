import SwiftUI

/// Mirrors InstructionsChoiceActivity/activity_instructions_choice.xml: same
/// welcome_gradient background, top-left white/indigo "Back" pill, and the
/// exact "Ready to Play?" / YES-NO button copy and colors. Routing logic
/// (push/replaceTop calls) is untouched - only the visual layer changed.
struct InstructionsChoiceView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()

            Button {
                router.pop()
            } label: {
                Text("Back")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0x1A237E))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(16)

            VStack(spacing: 0) {
                Text("Ready to Play?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                Text("Do you want to read the instructions?")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)

                Button {
                    router.push(.instructionsView(selection))
                } label: {
                    Text("YES, SHOW ME HOW")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: 0x1A237E))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 15)

                Button {
                    router.replaceTop(with: .game(selection))
                } label: {
                    Text("NO, I KNOW THE RULES")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: 0x333333))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white.opacity(0xAA / 255.0))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarHidden(true)
    }
}
