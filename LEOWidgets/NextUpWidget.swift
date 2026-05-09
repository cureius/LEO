import WidgetKit
import SwiftUI

/// Small: shows the single next item.
struct NextUpWidget: Widget {
    let kind = "NextUpWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LEOTimelineProvider()) { entry in
            NextUpWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Next Up")
        .description("Always see what's next.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextUpWidgetView: View {
    let entry: LEOEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Next Up", systemImage: "arrow.right.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let item = entry.snapshot.nextItem {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if let time = item.time {
                    Text(time, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("All clear")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
