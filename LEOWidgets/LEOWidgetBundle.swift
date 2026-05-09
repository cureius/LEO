import WidgetKit
import SwiftUI

@main
struct LEOWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NextUpWidget()
        QuickAddWidget()
        HabitRingWidget()
    }
}
