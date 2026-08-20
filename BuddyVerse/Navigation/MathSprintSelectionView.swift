import SwiftUI

/// Mirrors MathSprintSelectionActivity/activity_math_sprint_selection.xml:
/// pick a round length, straight to the game.
struct MathSprintSelectionView: View {
    @EnvironmentObject private var router: Router

    // activity_math_sprint_selection.xml is a flat solid #FF5722 background
    // with no @color/@drawable references - same in light and dark.
    private let rootBg = Color(hex: 0xFF5722)
    private let cancelButtonBg = Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)

    var body: some View {
        ZStack {
            rootBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Math Sprint")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                Text("Select Sprint Time:")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(.bottom, 40)

                ForEach([30, 60, 90], id: \.self) { seconds in
                    Button {
                        router.push(.game(GameSelection(gameType: "MATH", difficulty: String(seconds))))
                    } label: {
                        Text("\(seconds) Seconds")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(rootBg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, seconds == 90 ? 30 : 10)
                }

                Button("Back") { router.pop() }
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x333333))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(cancelButtonBg)
                    .buttonStyle(.plain)
            }
            .padding(20)
        }
        .navigationBarHidden(true)
    }
}
