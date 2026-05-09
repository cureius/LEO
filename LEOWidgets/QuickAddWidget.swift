import WidgetKit
import SwiftUI

/// Small / lock-screen: a single "+" button that deep-links into the capture surface.
struct QuickAddWidget: Widget {
    let kind = "QuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LEOTimelineProvider()) { entry in
            QuickAddWidgetView()
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Quick Add")
        .description("Tap to capture a new item in LEO.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct QuickAddWidgetView: View {
    var body: some View {
        Link(destination: URL(string: "leo://capture")!) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
                Text("Add to LEO")
                    .font(.caption2)
            }
        }
    }
}
