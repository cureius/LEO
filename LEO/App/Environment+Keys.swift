import SwiftUI

private struct ItemRepositoryKey: EnvironmentKey {
    static let defaultValue: ItemRepository? = nil
}

private struct HabitRepositoryKey: EnvironmentKey {
    static let defaultValue: HabitRepository? = nil
}

private struct TagRepositoryKey: EnvironmentKey {
    static let defaultValue: TagRepository? = nil
}

private struct NotificationManagerKey: EnvironmentKey {
    static let defaultValue: NotificationManager? = nil
}

extension EnvironmentValues {
    var itemRepository: ItemRepository? {
        get { self[ItemRepositoryKey.self] }
        set { self[ItemRepositoryKey.self] = newValue }
    }

    var habitRepository: HabitRepository? {
        get { self[HabitRepositoryKey.self] }
        set { self[HabitRepositoryKey.self] = newValue }
    }

    var tagRepository: TagRepository? {
        get { self[TagRepositoryKey.self] }
        set { self[TagRepositoryKey.self] = newValue }
    }

    var notificationManager: NotificationManager? {
        get { self[NotificationManagerKey.self] }
        set { self[NotificationManagerKey.self] = newValue }
    }
}
