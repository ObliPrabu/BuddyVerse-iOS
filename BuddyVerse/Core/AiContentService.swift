import Foundation

/// Mirrors AiGeneratingActivity.kt: calls the Gemini REST API directly (no
/// SDK) to write fresh jokes/riddles/trivia/conversation starters matching
/// the picked mood/age group. Any failure (no key, no network, malformed
/// response) returns nil so the caller falls back to built-in static content
/// - that fallback is a hard requirement of this pattern, not optional.
enum AiContentService {
    private static var apiKey: String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let key = plist["GeminiAPIKey"] as? String,
              !key.isEmpty else { return nil }
        return key
    }

    static func categoryName(for gameType: String) -> String {
        switch gameType {
        case "JOKES": return "jokes"
        case "RIDDLES": return "riddles"
        case "TRIVIA": return "trivia questions"
        case "CONVERSATION": return "conversation starters"
        default: return "content"
        }
    }

    /// Returns a batch of small JSON strings (one per item) the destination
    /// game screen knows how to decode, or nil if generation failed/was
    /// unavailable so the caller falls back to built-in content.
    static func generate(gameType: String, mood: String, ageGroup: String, difficulty: String) async -> [String]? {
        guard let apiKey else { return nil }

        let prompt = buildPrompt(gameType: gameType, mood: mood, ageGroup: ageGroup, difficulty: difficulty)
        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["responseMimeType": "application/json"]
        ]

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"),
              let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = root["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String,
                  let textData = text.data(using: .utf8),
                  let itemsArray = try JSONSerialization.jsonObject(with: textData) as? [[String: Any]]
            else { return nil }

            let result: [String] = itemsArray.compactMap { item in
                guard let itemData = try? JSONSerialization.data(withJSONObject: item),
                      let itemString = String(data: itemData, encoding: .utf8) else { return nil }
                return itemString
            }
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    private static func buildPrompt(gameType: String, mood: String, ageGroup: String, difficulty: String) -> String {
        let tone: String
        switch mood {
        case "HAPPY": tone = "upbeat, cheerful, and playful"
        case "SAD": tone = "gentle, comforting, and uplifting, meant to cheer someone up"
        case "BORED": tone = "surprising, fun, and extra entertaining"
        case "EXCITED": tone = "high-energy, hype, and exciting"
        default: tone = "fun and friendly"
        }

        // Everything must stay clean/appropriate either way - "adult" here
        // just means more grown-up humor and topics, not mature content.
        let audience = ageGroup == "ADULT"
            ? "adults. Use more grown-up humor, wordplay, and topics (like work, relationships, or everyday adult life), written a bit more cleverly - but it must still be completely clean and appropriate, no crude or mature content"
            : "kids. Use simple, easy-to-understand words and silly, wholesome humor that a child would enjoy"

        let challenge: String
        switch difficulty {
        case "EASY": challenge = "Keep it easy - simple, quick to get, no obscure references or tricky wordplay."
        case "HARD": challenge = "Make it genuinely challenging - clever, a bit obscure, and worth thinking about."
        default: challenge = "Keep it medium difficulty - not too easy, not too obscure."
        }

        switch gameType {
        case "JOKES":
            return "Write 8 short, clean jokes for a party-game app, written for \(audience). The tone should be \(tone). \(challenge) Return ONLY a JSON array, no markdown, no extra text, in exactly this format: [{\"setup\":\"...\",\"punchline\":\"...\"}]"
        case "RIDDLES":
            return "Write 8 fun, clean riddles for a party-game app, written for \(audience). The tone should be \(tone). \(challenge) Return ONLY a JSON array, no markdown, no extra text, in exactly this format: [{\"question\":\"...\",\"answer\":\"...\"}]"
        case "TRIVIA":
            return "Write 8 fun, clean trivia questions for a party-game app, written for \(audience), each with exactly 4 multiple choice options where only one is correct. The tone should be \(tone). \(challenge) Return ONLY a JSON array, no markdown, no extra text, in exactly this format: [{\"question\":\"...\",\"options\":[\"...\",\"...\",\"...\",\"...\"],\"answer\":\"...\"}] where \"answer\" is copied exactly, character for character, from one of the options."
        case "CONVERSATION":
            return "Write 8 fun, clean conversation-starter questions for friends to answer and share with each other, for a party-game app, written for \(audience). The tone should be \(tone). \(challenge) Return ONLY a JSON array, no markdown, no extra text, in exactly this format: [{\"question\":\"...\"}]"
        default:
            return "Write 8 short, clean, fun questions for a party-game app, written for \(audience). \(challenge) Return ONLY a JSON array in exactly this format: [{\"question\":\"...\"}]"
        }
    }
}
