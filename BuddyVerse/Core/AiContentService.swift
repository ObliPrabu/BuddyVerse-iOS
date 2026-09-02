import Foundation

/// Every game category's content always comes from its own built-in static
/// pool now - there is no AI generation path anymore. This just holds the
/// display name used for the "Getting your X ready..." loading text.
enum AiContentService {
    static func categoryName(for gameType: String) -> String {
        switch gameType {
        case "JOKES": return "jokes"
        case "RIDDLES": return "riddles"
        case "TRIVIA": return "trivia questions"
        case "CONVERSATION": return "conversation starters"
        default: return "content"
        }
    }
}
