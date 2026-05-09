import Foundation

/// A lightweight, JSON-serializable snapshot of LEO state written by the main app to the
/// App Group container. Widgets read this file — they cannot access SwiftData directly.
/// Schema versioned to allow forward evolution.
public struct WidgetSnapshot: Codable, Sendable {
    public let schemaVersion: Int       // bump when adding fields
    public let generatedAt: Date
    public let todayItems: [SnapshotItem]
    public let nextItem: SnapshotItem?
    public let habitRing: HabitRingSummary

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = .now,
        todayItems: [SnapshotItem],
        nextItem: SnapshotItem?,
        habitRing: HabitRingSummary
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.todayItems = todayItems
        self.nextItem = nextItem
        self.habitRing = habitRing
    }

    public struct SnapshotItem: Codable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let time: Date?
        public let typeSymbol: String   // SF Symbol name
        public let isCompleted: Bool

        public init(id: UUID, title: String, time: Date?, typeSymbol: String, isCompleted: Bool) {
            self.id = id
            self.title = title
            self.time = time
            self.typeSymbol = typeSymbol
            self.isCompleted = isCompleted
        }
    }

    public struct HabitRingSummary: Codable, Sendable {
        public let total: Int
        public let completed: Int
        public var progress: Double { total > 0 ? Double(completed) / Double(total) : 0 }

        public init(total: Int, completed: Int) {
            self.total = total
            self.completed = completed
        }
    }
}

// MARK: - Shared container URL

public enum WidgetSnapshotStore {
    public static let appGroupID = "group.com.theblueman.leo"

    public static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("widget_snapshot.json")
    }

    public static func write(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL else { return }
        let data = try? JSONEncoder().encode(snapshot)
        try? data?.write(to: url, options: .atomic)
    }

    public static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
