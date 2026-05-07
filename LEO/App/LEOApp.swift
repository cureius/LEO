import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.leo.app", category: "app")

@main
struct LEOApp: App {
    /// Nil until async initialization completes — keeps the main thread free
    /// at launch so SpringBoard scene connection succeeds.
    @State private var appEnvironment: AppEnvironment? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if let env = appEnvironment {
                    RootView()
                        .environment(env)
                        .modelContainer(env.persistenceController.container)
                } else {
                    // Lightweight splash while environment initializes
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
                // Run off the main actor so ModelContainer doesn't block scene connection
                let env = await Task.detached(priority: .userInitiated) {
                    AppEnvironment()
                }.value
                appEnvironment = env
                logger.info("AppEnvironment init complete")
            }
        }
    }
}
