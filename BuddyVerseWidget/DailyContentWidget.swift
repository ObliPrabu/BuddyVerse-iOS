import WidgetKit
import SwiftUI

/// Home-screen widget showing a joke or riddle of the day, drawn from
/// DailyContentPool (shared with the main app target - see that file's own
/// doc comment). Tapping the widget deep-links into the main app via
/// `buddyverse://daily/...` (handled by DeepLinkManager), landing directly
/// on JokesView/RiddlesView rather than the Welcome screen.
struct DailyContentEntry: TimelineEntry {
    let date: Date
    let pick: DailyContentPool.Pick
}

struct DailyContentProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyContentEntry {
        DailyContentEntry(date: Date(), pick: DailyContentPool.pick(for: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyContentEntry) -> Void) {
        completion(DailyContentEntry(date: Date(), pick: DailyContentPool.pick(for: Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyContentEntry>) -> Void) {
        let now = Date()
        let entry = DailyContentEntry(date: now, pick: DailyContentPool.pick(for: now))
        // Refresh shortly after local midnight so tomorrow's pick shows up
        // without waiting on iOS's own opportunistic refresh budget - a
        // small fixed offset rather than exactly midnight, so it lands
        // after the date has genuinely rolled over.
        let midnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct DailyContentWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyContentEntry

    private let gradientTop = Color(red: 0x6A / 255, green: 0x5A / 255, blue: 0xE0 / 255)
    private let gradientBottom = Color(red: 0x3A / 255, green: 0x1F / 255, blue: 0x6E / 255)

    var body: some View {
        content
            .widgetURL(deepLinkURL)
            .modifier(WidgetBackground(gradient: gradient))
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [gradientTop, gradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.pick.kind == .joke ? "\u{1F602} Joke of the Day" : "\u{1F914} Riddle of the Day")
                .font(.caption2.bold())
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)

            Text(entry.pick.primary)
                .font(.system(size: family == .systemSmall ? 13 : 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(family == .systemSmall ? 5 : 3)
                .minimumScaleFactor(0.85)

            if family != .systemSmall {
                Text(entry.pick.kind == .joke ? entry.pick.secondary : "Tap to see the answer in the app")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var deepLinkURL: URL? {
        URL(string: "buddyverse://daily/\(entry.pick.kind == .joke ? "jokes" : "riddles")")
    }
}

/// `.containerBackground(for:)` is the iOS 17+ required way to set a
/// widget's background; this extension's deployment floor is iOS 16.2 (see
/// project.yml, needed for the Live Activity), so pre-17 falls back to a
/// plain `.background()` - same pattern as the main app target's other
/// `#available`-gated view code (see CLAUDE.md's "iOS 14 compatibility
/// constraints" section).
private struct WidgetBackground: ViewModifier {
    let gradient: LinearGradient

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { gradient }
        } else {
            content.background(gradient)
        }
    }
}

struct DailyContentWidget: Widget {
    let kind: String = "DailyContentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyContentProvider()) { entry in
            DailyContentWidgetView(entry: entry)
        }
        .configurationDisplayName("Joke / Riddle of the Day")
        .description("A fresh joke or riddle every day - tap to open it in BuddyVerse.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
