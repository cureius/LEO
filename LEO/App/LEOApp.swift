import SwiftUI
import SwiftData
import BackgroundTasks
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "app")

private let bgRefreshID = "com.theblueman.leo.refresh"

@main
struct LEOApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appEnvironment: AppEnvironment? = nil
    // Created on main thread after appEnvironment is ready
    @State private var locationReminderManager: LocationReminderManager? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if let env = appEnvironment {
                    RootView()
                        .environment(env)
                        .modelContainer(env.persistenceController.container)
                } else {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text("LEO")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundStyle(.white)
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
            }
            .task {
                guard appEnvironment == nil else { return }
                logger.info("AppEnvironment init start")
                // Run heavy init off main thread
                let env = await Task.detached(priority: .userInitiated) {
                    AppEnvironment()
                }.value
                appEnvironment = env
                logger.info("AppEnvironment init complete")

                // Location manager must be created on the main thread
                locationReminderManager = LocationReminderManager(notificationManager: env.notificationManager)

                // Request notification permission
                _ = await env.notificationManager.requestAuthorization()

                // Top up notification window
                if let items = try? await env.itemRepository.fetch() {
                    await env.notificationManager.sync(for: items)
                }

                scheduleAppRefresh()

                // Restore saved calendar/reminder subscriptions so the first sync
                // uses the user's persisted selection (not an empty set).
                let savedCalIDs = Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_calendar_ids") ?? [])
                let savedRemIDs = Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_reminder_list_ids") ?? [])
                await env.eventKitBridge.subscribe(calendarIDs: savedCalIDs, reminderListIDs: savedRemIDs)

                // Begin observing EKEventStoreChanged so external edits (Google/iCloud)
                // flow into LEO without a manual sync.
                await env.calendarSyncCoordinator.start()
                await env.calendarSyncCoordinator.syncOnForeground()

                // Re-sync notifications whenever an item changes in-app.
                // Runs the whole body on @MainActor so no off-thread continuation surprise.
                for await _ in NotificationCenter.default.notifications(named: .leoDataDidChange) {
                    await MainActor.run { } // ensure we're back on main before the next hop
                    guard let currentItems = try? await env.itemRepository.fetch() else { continue }
                    logger.info("leoDataDidChange → re-syncing \(currentItems.count) items")
                    await env.notificationManager.sync(for: currentItems)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, let env = appEnvironment else { return }
                Task { await env.calendarSyncCoordinator.syncOnForeground() }
            }
        }
        .backgroundTask(.appRefresh(bgRefreshID)) {
            guard let env = appEnvironment else { return }
            logger.info("BGAppRefresh fired — calendar sync + notification top-up")
            await env.calendarSyncCoordinator.syncForBackgroundTask()
            if let items = try? await env.itemRepository.fetch() {
                await env.notificationManager.sync(for: items)
            }
            scheduleAppRefresh()
        }
    }
}

// MARK: - Background task scheduling

/// 15 min is the iOS-suggested earliest window for BGAppRefreshTask. The system
/// decides the actual cadence (typically 30–120 min in real conditions); 15 min
/// is the hint for "as soon as reasonable" and is what we want for calendar sync.
private func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: bgRefreshID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
        try BGTaskScheduler.shared.submit(request)
        logger.info("BGAppRefresh scheduled for ~15m from now")
    } catch {
        logger.warning("BGAppRefresh scheduling failed: \(error)")
    }
}
