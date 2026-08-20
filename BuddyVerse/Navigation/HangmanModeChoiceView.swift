import SwiftUI

/// Mirrors HangmanModeChoiceActivity/activity_hangman_mode_choice.xml: only
/// the HOST picks PICKER vs RACE; the guest waits and is carried along
/// automatically once the host picks.
struct HangmanModeChoiceView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router
    @State private var isHost = InternetConnectionManager.shared.isHost()

    // activity_hangman_mode_choice.xml is a flat solid #607D8B background
    // with no @color/@drawable references - same in light and dark.
    private let rootBg = Color(hex: 0x607D8B)
    private let descriptionColor = Color.white.opacity(0xDD / 255.0)
    private let raceButtonBg = Color(hex: 0xFF9800)
    private let cancelButtonBg = Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)

    var body: some View {
        ZStack {
            rootBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Hangman")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                if isHost {
                    Text("How do you want to play?")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)

                    Button {
                        choose("PICKER")
                    } label: {
                        Text("Have Your Friend Choose Your Word")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(rootBg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)

                    Text("Take turns picking a secret word for the other person to guess.")
                        .font(.system(size: 13))
                        .foregroundColor(descriptionColor)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 25)

                    Button {
                        choose("RACE")
                    } label: {
                        Text("Race to Get the Random Word")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(raceButtonBg)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)

                    Text("Both phones get the same random word and category - whoever guesses it first wins!")
                        .font(.system(size: 13))
                        .foregroundColor(descriptionColor)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 30)
                } else {
                    Text("Waiting for your friend to choose how to play...")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }

                Button("Back") {
                    InternetConnectionManager.shared.clearWordModeObserver()
                    router.pop()
                }
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
        .onAppear {
            if !isHost {
                InternetConnectionManager.shared.observeWordMode { wordMode in
                    DispatchQueue.main.async { choose(wordMode, alreadyChosenRemotely: true) }
                }
            }
        }
        .onDisappear {
            InternetConnectionManager.shared.clearWordModeObserver()
        }
    }

    private func choose(_ wordMode: String, alreadyChosenRemotely: Bool = false) {
        if !alreadyChosenRemotely {
            InternetConnectionManager.shared.chooseWordMode(wordMode)
        }
        InternetConnectionManager.shared.clearWordModeObserver()
        var next = selection
        next.wordMode = wordMode
        router.replaceTop(with: .instructionsChoice(next))
    }
}
