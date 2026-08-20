import SwiftUI

/// Mirrors ConversationActivity: shows a conversation-starter question to
/// answer. The "What others are saying" section shows REAL answers that were
/// actually typed in for that exact question before (saved right on this
/// device, mirroring the Android SharedPreferences store) - never made-up or
/// AI-generated examples. If nobody has answered a question yet, it just
/// says so honestly instead of showing a fake response.
struct ConversationView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    private let pool: [String]
    @State private var remaining: [String]
    @State private var current: String
    @State private var answerText: String = ""
    @State private var savedAnswers: [String] = []

    // Namespaced so this never collides with any other UserDefaults key used
    // elsewhere in the app - mirrors Android's dedicated
    // "conversation_answers" SharedPreferences file, which is its own isolated
    // storage bucket.
    private static let defaultsPrefix = "conversation_answers::"

    init(selection: GameSelection) {
        self.selection = selection
        let pool = Self.buildPool(from: selection.aiItems)
        self.pool = pool
        var shuffled = pool.shuffled()
        let first = shuffled.isEmpty ? "Tap for a question!" : shuffled.removeLast()
        _remaining = State(initialValue: shuffled)
        _current = State(initialValue: first)
    }

    // activity_conversation.xml: solid #FF9800 background, no dark-mode
    // override, so this looks identical regardless of the app's theme
    // setting. Unlike Jokes/Riddles/Trivia, the root LinearLayout has no
    // android:gravity="center", so content is top-aligned, not vertically
    // centered.
    private let screenBg = Color(hex: 0xFF9800)
    private let buttonTextDark = Color(hex: 0x333333)
    // #AADDDDDD - a light gray at ~67% alpha, not plain white-with-opacity.
    private let backButtonBg = Color(hex: 0xDDDDDD, opacity: 170.0 / 255.0)

    var body: some View {
        ZStack {
            screenBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    router.pop()
                } label: {
                    Text("Back")
                        .font(.system(size: 14))
                        .foregroundColor(buttonTextDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backButtonBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)

                Text("Conversation Starters \u{1F4AC}")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 20)

                Text(current)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                    .padding(.bottom, 15)

                // Android's EditText has a white-tinted underline (the
                // default EditText background drawable, just recolored) and
                // no filled box - it isn't a bordered/material text field.
                TextEditor(text: $answerText)
                    .foregroundColor(.white)
                    .accentColor(.white)
                    .frame(minHeight: 60)
                    // `.scrollContentBackground(.hidden)` needs iOS 16 - the
                    // appearance-proxy trick makes a TextEditor's backing
                    // UITextView transparent on every iOS version instead.
                    // Only TextEditor in the app, so a global proxy is safe.
                    .onAppear { UITextView.appearance().backgroundColor = .clear }
                    // The labeled-alignment `.overlay(alignment:) {}` needs
                    // iOS 15 - these are the `.overlay(_:alignment:)`
                    // (iOS 13+) equivalents.
                    .overlay(
                        Group {
                            if answerText.isEmpty {
                                Text("Type your answer here...")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: 0xE0E0E0))
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
                    .overlay(
                        Rectangle().fill(Color.white).frame(height: 1),
                        alignment: .bottom
                    )
                    .padding(.bottom, 15)

                Button {
                    advanceToNextQuestion()
                } label: {
                    Text("Next Question")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(screenBg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)

                Text("What others are saying:")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if savedAnswers.isEmpty {
                            Text("No one has answered this one yet - yours could be the first!")
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(170.0 / 255.0))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(10)
                        } else {
                            ForEach(savedAnswers, id: \.self) { answer in
                                Text("\u{1F4AC} \(answer)")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color.black.opacity(34.0 / 255.0))
                            }
                        }
                    }
                    .padding(10)
                }
                .background(Color.black.opacity(0x33 / 255.0))
            }
            .padding(20)
        }
        .navigationBarHidden(true)
        .onAppear { refreshSavedAnswers() }
    }

    private func advanceToNextQuestion() {
        // Save whatever was just typed as a REAL answer to the question
        // that's about to disappear, before moving on.
        let justAnsweredQuestion = current
        let myAnswer = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !myAnswer.isEmpty {
            saveAnswer(myAnswer, for: justAnsweredQuestion)
        }
        showNextQuestion()
    }

    private func showNextQuestion() {
        // Starters get shuffled into this "still to show" pile. Once a
        // starter is shown it's removed from the pile so it can't repeat -
        // once the pile runs out, it reshuffles a fresh pile so the button
        // keeps working.
        if remaining.isEmpty {
            remaining = pool.shuffled()
        }
        current = remaining.removeLast()
        answerText = ""
        refreshSavedAnswers()
    }

    // MARK: - Per-question saved answers (UserDefaults, mirrors SharedPreferences)

    private func saveAnswer(_ answer: String, for question: String) {
        let key = Self.defaultsPrefix + question
        let existing = UserDefaults.standard.string(forKey: key) ?? ""
        var answers = existing.isEmpty ? [] : existing.components(separatedBy: "|||")
        answers.append(answer)
        // Keep only the most recent 20 so this doesn't grow forever.
        let trimmed = answers.count > 20 ? Array(answers.suffix(20)) : answers
        UserDefaults.standard.set(trimmed.joined(separator: "|||"), forKey: key)
    }

    private func loadSavedAnswers(for question: String) -> [String] {
        let key = Self.defaultsPrefix + question
        let existing = UserDefaults.standard.string(forKey: key) ?? ""
        return existing.isEmpty ? [] : existing.components(separatedBy: "|||")
    }

    private func refreshSavedAnswers() {
        // Most recent answers first, capped at 5 - matches Android's display.
        savedAnswers = Array(loadSavedAnswers(for: current).reversed().prefix(5))
    }

    // MARK: - Pool building

    private struct AiConversationItem: Decodable {
        let question: String?
    }

    private static func buildPool(from aiItems: [String]?) -> [String] {
        let aiStarters: [String] = (aiItems ?? []).compactMap { raw in
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(AiConversationItem.self, from: data) else { return nil }
            let q = (obj.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return q.isEmpty ? nil : q
        }
        if !aiStarters.isEmpty { return aiStarters }
        return allStarters
    }

    // MARK: - Static fallback pool (used whenever AI generation isn't
    // available - ported verbatim from ConversationActivity.kt's allStarters
    // list, the baseline content most users will actually see).
    private static let allStarters: [String] = [
        "If you could have any superpower, what would it be?",
        "What is your favorite travel memory?",
        "What's the best piece of advice you've ever received?",
        "If you could meet any historical figure, who would it be?",
        "What is your go-to comfort food?",
        "If you could live anywhere in the world, where would it be?",
        "What is your proudest accomplishment?",
        "What's the best book you've ever read?",
        "If you could only eat one meal for the rest of your life, what would it be?",
        "What's your favorite way to spend a weekend?",
        "If you could win an Olympic medal, what sport would it be for?",
        "What's the most beautiful place you've ever seen?",
        "What's your favorite hobby?",
        "What's the best gift you've ever received?",
        "What's your favorite season?",
        "What's the most unusual thing you've ever eaten?",
        "What's your favorite movie of all time?",
        "If you could be any animal, what would you be?",
        "What's your favorite childhood memory?",
        "What's the best concert you've ever been to?",
        "What's your favorite board game?",
        "If you could travel back in time, when would you go?",
        "What's your favorite type of music?",
        "What's the most adventurous thing you've ever done?",
        "What's your favorite place in your home?",
        "If you could have dinner with anyone, who would it be?",
        "What's your favorite subject in school?",
        "What's the best part of your day?",
        "What's your favorite ice cream flavor?",
        "If you could learn any language, what would it be?",
        "What's your favorite holiday?",
        "What's the most important thing you've learned recently?",
        "What's your favorite video game?",
        "If you could be famous for one thing, what would it be?",
        "What's your favorite quote?",
        "What's the best trip you've ever taken?",
        "What's your favorite vegetable?",
        "If you could have any job in the world, what would it be?",
        "What's your favorite thing about yourself?",
        "What's the most interesting fact you know?",
        "What's your favorite flower?",
        "If you could be a character in any book, who would you be?",
        "What's your favorite sport to watch?",
        "What's the best meal you've ever had?",
        "What's your favorite planet?",
        "If you could invent something, what would it be?",
        "What's your favorite color?",
        "What's the best way to relax?",
        "What's your favorite fruit?",
        "If you could live in any era, which would it be?",
        "What's your favorite thing to do with friends?",
        "What's the most inspiring thing you've ever seen?",
        "What's your favorite instrument?",
        "If you could have any talent, what would it be?",
        "What's your favorite smell?",
        "What's the best advice you'd give to your younger self?",
        "What's your favorite dessert?",
        "If you could build a house out of anything, what would it be?",
        "What's your favorite thing to do on a rainy day?",
        "What's the most thoughtful thing someone has done for you?",
        "What's your favorite animal at the zoo?",
        "If you could change one thing about the world, what would it be?",
        "What's your favorite thing to learn about?",
        "What's the best surprise you've ever had?",
        "What's your favorite song?",
        "If you could meet any fictional character, who would it be?",
        "What's your favorite way to stay active?",
        "What's the most rewarding part of your life?",
        "What's your favorite type of weather?",
        "If you could go to space, would you?",
        "What's your favorite piece of technology?",
        "What's the best thing about your community?",
        "What's your favorite app?",
        "If you could be an expert in any field, what would it be?",
        "What's your favorite thing to cook?",
        "What's the most creative thing you've ever done?",
        "What's your favorite mythical creature?",
        "If you could have a conversation with your future self, what would you ask?",
        "What's your favorite charity?",
        "What's the best lesson you've ever learned?",
        "What's your favorite candy?",
        "If you could inhabit any fictional world, which would it be?",
        "What's your favorite thing to do in the morning?",
        "What's the most courageous thing you've ever done?",
        "What's your favorite memory with your family?",
        "If you could give everyone in the world one thing, what would it be?",
        "What's your favorite part of nature?",
        "What's the best discovery you've ever made?",
        "What's your favorite way to express yourself?",
        "If you could win any award, what would it be?",
        "What's your favorite thing about your best friend?",
        "What's the most peaceful place you've ever been?",
        "What's your favorite game from your childhood?",
        "If you could be a professional athlete, which sport would it be?",
        "What's your favorite thing to do before bed?",
        "What's the most valuable lesson you've learned from a failure?",
        "What's your favorite local business?",
        "If you could have any collection, what would you collect?",
        "What's your favorite thing to do at the beach?",
        "What's the best way to make a new friend?"
    ]
}
