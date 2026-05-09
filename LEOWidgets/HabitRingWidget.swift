import WidgetKit
import SwiftUI

/// Medium / lock-screen: shows today's habit completion ring.
struct HabitRingWidget: Widget {
    let kind = "HabitRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LEOTimelineProvider()) { entry in
            HabitRingWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Habit Ring")
        .description("Track your habits at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct HabitRingWidgetView: View {
    let entry: LEOEntry

    var ring: WidgetSnapshot.HabitRingSummary { entry.snapshot.habitRing }

    var body: some View {
        HStack(spacing: 16) {
            // Ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: ring.progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(ring.progress * 100))%")
                    .font(.caption2.bold())
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text("Habits")
                    .font(.headline)
                Text("\(ring.completed) of \(ring.total) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
