import Foundation
import SwiftUI

/// Central DI container wired at the app level and distributed via @Environment.
@Observable
final class AppEnvironment {
    let persistenceController: PersistenceController
    let itemRepository: ItemRepository
    let habitRepository: HabitRepository
    let tagRepository: TagRepository
    let notificationManager: NotificationManager

    init(useInMemory: Bool = false) {
        let controller = PersistenceController(useInMemory: useInMemory)
        self.persistenceController = controller
        self.itemRepository = ItemRepository(controller: controller)
        self.habitRepository = HabitRepository(controller: controller)
        self.tagRepository = TagRepository(controller: controller)
        self.notificationManager = NotificationManager()
    }
}
