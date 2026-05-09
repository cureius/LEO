import WidgetKit
import SwiftUI

/// Medium/Large: shows the next 5 items for today.
struct TodayWidget: Widget {
    let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LEOTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("See your upcoming items at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    let entry: LEOEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(.primary)

            if entry.snapshot.todayItems.isEmpty {
                Text("Nothing scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.snapshot.todayItems.prefix(5)) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.typeSymbol)
                            .font(.caption)
                            .foregroundStyle(item.isCompleted ? Color.secondary : Color.accentColor)
                        Text(item.title)
                            .font(.caption)
                            .strikethrough(item.isCompleted)
                            .lineLimit(1)
                        Spacer()
                        if let time = item.time {
                            Text(time, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
