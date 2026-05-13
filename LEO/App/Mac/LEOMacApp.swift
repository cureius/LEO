import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo.mac", category: "app")

@main
struct LEOMacApp: App {
    @State private var appEnvironment: AppEnvironment? = nil

    var body: some Scene {
        WindowGroup("LEO") {
            Group {
                if let env = appEnvironment {
                    MacRootView()
                        .environment(env)
                        .modelContainer(env.persistenceController.container)
                } else {
                    loadingView
                }
            }
            .task {
                guard appEnvironment == nil else { return }
                logger.info("Mac AppEnvironment init start")
                let env = await Task.detached(priority: .userInitiated) {
                    AppEnvironment()
                }.value
                appEnvironment = env
                logger.info("Mac AppEnvironment init complete")

                _ = await env.notificationManager.requestAuthorization()

                if let items = try? await env.itemRepository.fetch() {
                    await env.notificationManager.sync(for: items)
                }

                let savedCalIDs = Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_calendar_ids") ?? [])
                let savedRemIDs = Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_reminder_list_ids") ?? [])
                await env.eventKitBridge.subscribe(calendarIDs: savedCalIDs, reminderListIDs: savedRemIDs)
                await env.calendarSyncCoordinator.start()
                await env.calendarSyncCoordinator.syncOnForeground()

                for await _ in NotificationCenter.default.notifications(named: .leoDataDidChange) {
                    await MainActor.run {}
                    guard let currentItems = try? await env.itemRepository.fetch() else { continue }
                    logger.info("leoDataDidChange → re-syncing \(currentItems.count) items")
                    await env.notificationManager.sync(for: currentItems)
                }
            }
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            MacCommands()
        }
        Settings {
            MacSettingsPlaceholder()
        }
    }

    private var loadingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("LEO")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                ProgressView().tint(.white)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Settings placeholder (full impl in MM8)

private struct MacSettingsPlaceholder: View {
    var body: some View {
        TabView {
            Text("General — MM8-T04")
                .tabItem { Label("General", systemImage: "gearshape") }
            Text("Calendar — MM8-T05")
                .tabItem { Label("Calendar", systemImage: "calendar") }
            Text("AI — MM8-T05")
                .tabItem { Label("AI", systemImage: "sparkles") }
            Text("Fitness — MM8-T05")
                .tabItem { Label("Fitness", systemImage: "figure.run") }
            Text("Keyboard — MM8-T06")
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
        }
        .frame(minWidth: 600, minHeight: 480)
        .padding()
    }
}

// MARK: - Commands placeholder (full impl in MM2-T03)

struct MacCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Item…") {
                NotificationCenter.default.post(name: .leoOpenQuickAdd, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            Button("Today")    { postSection(.today)   }.keyboardShortcut("1", modifiers: .command)
            Button("Inbox")    { postSection(.inbox)   }.keyboardShortcut("2", modifiers: .command)
            Button("Habits")   { postSection(.habits)  }.keyboardShortcut("3", modifiers: .command)
            Button("Ask LEO")  { postSection(.ask)     }.keyboardShortcut("4", modifiers: .command)
            Button("Fitness")  { postSection(.fitness) }.keyboardShortcut("5", modifiers: .command)
            Divider()
            Button("Toggle Inspector") {
                NotificationCenter.default.post(name: .leoToggleInspector, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.control, .option, .command])
        }
        #if DEBUG
        CommandGroup(after: .windowList) {
            Button("Debug Menu") {
                NotificationCenter.default.post(name: .leoOpenDebugMenu, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift, .option])
        }
        #endif
    }

    private func postSection(_ section: SidebarSection) {
        NotificationCenter.default.post(name: .leoSelectSidebarSection, object: section)
    }
}
