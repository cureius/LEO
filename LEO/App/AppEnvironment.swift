import Foundation
import SwiftUI
import UserNotifications

/// Central DI container wired at the app level and distributed via @Environment.
/// Initialized off the main thread (Task.detached in LEOApp); all stored services
/// are actors or thread-safe types.
@Observable
final class AppEnvironment {
    let persistenceController: PersistenceController
    let itemRepository: ItemRepository
    let habitRepository: HabitRepository
    let tagRepository: TagRepository
    let seriesRepository: SeriesRepository
    let notificationManager: NotificationManager
    let travelTimePreReminder: TravelTimePreReminder
    let eventKitBridge: EventKitBridge
    let eventKitWriteBack: EventKitWriteBack
    let calendarSyncCoordinator: CalendarSyncCoordinator
    let claudeClient: ClaudeClient
    let weeklyReviewGenerator: WeeklyReviewGenerator
    let alarmEngine: AlarmEngine
    let alarmActivityManager: AlarmActivityManager
    // Strong reference so delegate isn't deallocated
    let notificationDelegate: NotificationDelegate

    init(useInMemory: Bool = false) {
        let controller = PersistenceController(useInMemory: useInMemory)
        self.persistenceController = controller
        self.itemRepository = ItemRepository(controller: controller)
        self.habitRepository = HabitRepository(controller: controller)
        self.tagRepository = TagRepository(controller: controller)
        self.seriesRepository = SeriesRepository(controller: controller)

        let nm = NotificationManager()
        self.notificationManager = nm
        self.travelTimePreReminder = TravelTimePreReminder(notificationManager: nm)
        let bridge = EventKitBridge(itemRepository: itemRepository)
        self.eventKitBridge = bridge
        self.eventKitWriteBack = EventKitWriteBack()
        self.calendarSyncCoordinator = CalendarSyncCoordinator(bridge: bridge)
        let claude = ClaudeClient()
        self.claudeClient = claude
        self.weeklyReviewGenerator = WeeklyReviewGenerator(
            itemRepository: itemRepository,
            habitRepository: habitRepository,
            claudeClient: claude
        )
        self.alarmEngine = AlarmEngine(notificationManager: nm)
        self.alarmActivityManager = AlarmActivityManager()

        let delegate = NotificationDelegate(itemRepository: itemRepository, notificationManager: nm)
        self.notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }
}
