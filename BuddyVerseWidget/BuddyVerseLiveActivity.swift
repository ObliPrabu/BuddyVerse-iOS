import ActivityKit
import WidgetKit
import SwiftUI

/// Renders the "you vs them" Live Activity LiveActivityManager starts in the
/// main app - the Lock Screen / banner presentation plus every Dynamic
/// Island state (expanded, compact, minimal). This whole file only ever
/// runs on iOS 16.2+ (this target's own deployment floor - see
/// project.yml), so none of the `@available` guards the main app target
/// needs are necessary here.
struct BuddyVerseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BuddyVerseActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(indigo)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    nameColumn(label: "You", name: context.state.myName, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    nameColumn(label: "Opponent", name: context.state.opponentNames, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("VS")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.gameName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            } compactLeading: {
                Text(initials(context.state.myName))
                    .font(.caption2.bold())
            } compactTrailing: {
                Text(initials(context.state.opponentNames))
                    .font(.caption2.bold())
            } minimal: {
                Text("🎮")
            }
        }
    }

    private let indigo = Color(red: 0x1A / 255, green: 0x23 / 255, blue: 0x7E / 255)

    private func lockScreenView(context: ActivityViewContext<BuddyVerseActivityAttributes>) -> some View {
        VStack(spacing: 6) {
            Text(context.attributes.gameName)
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.7))
            HStack(spacing: 12) {
                Text(context.state.myName)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Text("VS")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.6))
                Text(context.state.opponentNames)
                    .font(.title3.bold())
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    private func nameColumn(label: String, name: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(name)
                .font(.headline)
                .lineLimit(1)
        }
    }

    /// A short 1-2 letter tag for the tiny compact Dynamic Island slots,
    /// which have room for only a few characters - falls back to the first
    /// letter alone if there's no space to split on (e.g. a single name).
    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))"
        }
        return String(name.prefix(2))
    }
}
