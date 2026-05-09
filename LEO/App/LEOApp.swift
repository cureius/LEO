import SwiftUI
import SwiftData
import BackgroundTasks
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "app")

private let bgRefreshID = "com.theblueman.leo.refresh"

@main
struct LEOApp: App {
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
            }
        }
        .backgroundTask(.appRefresh(bgRefreshID)) {
            guard let env = appEnvironment else { return }
            logger.info("BGAppRefresh fired — topping up notification window")
            if let items = try? await env.itemRepository.fetch() {
                await env.notificationManager.sync(for: items)
            }
            scheduleAppRefresh()
        }
    }
}

// MARK: - Background task scheduling

private func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: bgRefreshID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 3600)
    do {
        try BGTaskScheduler.shared.submit(request)
        logger.info("BGAppRefresh scheduled for ~24h from now")
    } catch {
        logger.warning("BGAppRefresh scheduling failed: \(error)")
    }
}
