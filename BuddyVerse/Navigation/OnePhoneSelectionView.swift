import SwiftUI

/// Mirrors OnePhoneSelectionActivity/activity_one_phone_selection.xml: a solid
/// green full-screen background, a white "Back" pill pinned top-left, and a
/// centered "One Phone Mode / With a friend?" Yes/No choice using Android's
/// exact button colors and copy (no separate "Cancel" control on Android -
/// just the one Back button).
struct OnePhoneSelectionView: View {
    let gameType: String
    @EnvironmentObject private var router: Router

    private let screenBg = Color(hex: 0x4CAF50)

    private var noBotLabel: String {
        GameCatalog.soloGamesWithNoBot.contains(gameType) ? "No (Play by yourself)" : "No (Play vs Bot)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            screenBg.ignoresSafeArea()

            Button {
                router.pop()
            } label: {
                Text("Back")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(screenBg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(16)

            VStack(spacing: 0) {
                Text("One Phone Mode")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                Text("With a friend?")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .padding(.bottom, 30)

                Button {
                    router.push(.friendTypeChoice(gameType: gameType))
                } label: {
                    Text("YES")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(screenBg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)

                if !GameCatalog.socialItems.contains(gameType) {
                    Button {
                        router.push(.botDifficulty(gameType: gameType))
                    } label: {
                        Text(noBotLabel)
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: 0x333333))
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color.white.opacity(0xAA / 255.0))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarHidden(true)
    }
}
