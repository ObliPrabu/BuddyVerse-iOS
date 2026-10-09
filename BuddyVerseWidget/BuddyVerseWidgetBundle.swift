import WidgetKit
import SwiftUI

@main
struct BuddyVerseWidgetBundle: WidgetBundle {
    var body: some Widget {
        BuddyVerseLiveActivity()
        DailyContentWidget()
    }
}
