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

    /// useInMemory defaults to true in DEBUG so the simulator always gets a
    /// clean fast-boot without hitting the SwiftData file lock issue seen in
    /// Xcode 15 simulator. Flip to false once on-disk persistence is verified.
    init(useInMemory: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()) {
        let controller = PersistenceController(useInMemory: useInMemory)
        self.persistenceController = controller
        self.itemRepository = ItemRepository(controller: controller)
        self.habitRepository = HabitRepository(controller: controller)
        self.tagRepository = TagRepository(controller: controller)
        self.notificationManager = NotificationManager()
    }
}
