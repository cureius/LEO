import Foundation
import WidgetKit

// MARK: - Shared snapshot loader (widget-side)

func loadSnapshot() -> WidgetSnapshot {
    WidgetSnapshotStore.read() ?? WidgetSnapshot(
        todayItems: [],
        nextItem: nil,
        habitRing: WidgetSnapshot.HabitRingSummary(total: 0, completed: 0)
    )
}

// MARK: - Timeline entry

struct LEOEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Shared timeline provider

struct LEOTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LEOEntry {
        LEOEntry(date: .now, snapshot: placeholderSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (LEOEntry) -> Void) {
        completion(LEOEntry(date: .now, snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LEOEntry>) -> Void) {
        let snapshot = loadSnapshot()
        var entries: [LEOEntry] = []
        var date = Date.now

        // Materialize timeline for the next 24h, refreshing at each item's start time
        entries.append(LEOEntry(date: date, snapshot: snapshot))
        for item in snapshot.todayItems {
            if let time = item.time, time > date {
                entries.append(LEOEntry(date: time, snapshot: snapshot))
            }
        }

        // Also add a 15-minute cadence refresh
        for i in 1...96 {
            date = Date.now.addingTimeInterval(Double(i) * 15 * 60)
            entries.append(LEOEntry(date: date, snapshot: loadSnapshot()))
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    private func placeholderSnapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            todayItems: [
                WidgetSnapshot.SnapshotItem(id: UUID(), title: "Team standup", time: .now.addingTimeInterval(3600), typeSymbol: "calendar", isCompleted: false),
                WidgetSnapshot.SnapshotItem(id: UUID(), title: "Review PR", time: nil, typeSymbol: "checklist", isCompleted: false)
            ],
            nextItem: WidgetSnapshot.SnapshotItem(id: UUID(), title: "Team standup", time: .now.addingTimeInterval(3600), typeSymbol: "calendar", isCompleted: false),
            habitRing: WidgetSnapshot.HabitRingSummary(total: 5, completed: 3)
        )
    }
}
