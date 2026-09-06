import SwiftUI
import SwiftData
import EventKit
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo.mac", category: "app")

@main
struct LEOMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appEnvironment: AppEnvironment? = nil
    @State private var hotkeyManager = GlobalHotkeyManager()
    @State private var captureWindowController = FloatingCaptureWindowController()

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
            .task { await bootApp() }
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            MacCommands()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let env = appEnvironment else { return }
            Task { await env.calendarSyncCoordinator.syncOnForeground() }
            #if canImport(Supabase)
            Task { await LiveSyncController.shared.syncOnForeground() }
            #endif
        }

        // MenuBar status + capture
        MenuBarExtra {
            if let env = appEnvironment {
                MenuBarCaptureView()
                    .environment(env)
            } else {
                ProgressView().padding()
            }
        } label: {
            Image(systemName: "sun.max")
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let env = appEnvironment {
                MacSettingsScene()
                    .environment(env)
            } else {
                ProgressView().padding(40)
            }
        }
    }

    // MARK: - Boot

    private func bootApp() async {
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

        // Request calendar/reminder access on the main actor.
        // EKEventStore.requestFullAccessToEvents/Reminders must run on the main thread
        // on macOS to trigger the system permission dialog. Routing through the
        // EventKitBridge actor (which uses a background executor) silently skips
        // the dialog — the app never appears in System Settings → Calendars.
        await requestCalendarAccess()

        let savedCalIDs = Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_calendar_ids") ?? [])
        let savedRemIDs = Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_reminder_list_ids") ?? [])
        await env.eventKitBridge.subscribe(calendarIDs: savedCalIDs, reminderListIDs: savedRemIDs)
        await env.calendarSyncCoordinator.start()
        await env.calendarSyncCoordinator.syncOnForeground()

        // Cloud sync (Supabase) — live for the whole app lifetime.
        #if canImport(Supabase)
        LiveSyncController.shared.configure(
            itemRepository: env.itemRepository,
            habitRepository: env.habitRepository,
            bodyProfileRepository: env.bodyProfileRepository
        )
        await LiveSyncController.shared.startIfSignedIn()
        #endif

        // Background sync using NSBackgroundActivityScheduler (macOS equivalent of BGAppRefreshTask)
        let activity = NSBackgroundActivityScheduler(identifier: "com.theblueman.leo.refresh")
        activity.interval = 30 * 60
        activity.repeats = true
        activity.qualityOfService = .utility
        activity.schedule { completion in
            Task { @MainActor in
                await env.calendarSyncCoordinator.syncForBackgroundTask()
                if let items = try? await env.itemRepository.fetch() {
                    await env.notificationManager.sync(for: items)
                }
                completion(.finished)
            }
        }

        // Global hotkey (requires Accessibility permission)
        await MainActor.run {
            hotkeyManager.start { [captureWindowController] in
                captureWindowController.toggle(with: env)
            }
        }

        // Manual refresh (⌘R). Pulls EventKit again and reconciles the cloud — the
        // views' own refresh only re-reads the local store, so a new calendar event
        // would never appear without this.
        Task {
            for await _ in NotificationCenter.default.notifications(named: .leoRefreshRequested) {
                logger.info("Manual refresh requested")
                await env.calendarSyncCoordinator.syncNow()
                #if canImport(Supabase)
                await LiveSyncController.shared.syncOnForeground()
                #endif
                // Always fire, even if a sync step above failed, so the toolbar
                // spinner can never get stuck spinning.
                NotificationCenter.default.post(name: .leoRefreshCompleted, object: nil)
            }
        }

        // Re-sync notifications on data changes
        for await _ in NotificationCenter.default.notifications(named: .leoDataDidChange) {
            await MainActor.run {}
            guard let items = try? await env.itemRepository.fetch() else { continue }
            logger.info("leoDataDidChange → re-syncing \(items.count) items")
            await env.notificationManager.sync(for: items)
        }
    }

    /// Requests calendar and reminder access on the main actor.
    /// Uses the completion-based requestAccess(to:) — more reliable than
    /// requestFullAccessToEvents() on macOS 26 where the async variant silently
    /// fails to create a TCC entry.
    @MainActor
    private func requestCalendarAccess() async {
        let store = EKEventStore()
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.requestAccess(to: .event) { granted, error in
                    logger.info("Calendar access result: granted=\(granted), error=\(String(describing: error))")
                    cont.resume()
                }
            }
        }
        if EKEventStore.authorizationStatus(for: .reminder) != .fullAccess {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.requestAccess(to: .reminder) { granted, error in
                    logger.info("Reminders access result: granted=\(granted), error=\(String(describing: error))")
                    cont.resume()
                }
            }
        }
        logger.info("Post-request: calendar=\(EKEventStore.authorizationStatus(for: .event).rawValue) reminders=\(EKEventStore.authorizationStatus(for: .reminder).rawValue)")
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

// MARK: - Floating capture window

@MainActor
final class FloatingCaptureWindowController {
    private var window: NSWindow?

    func toggle(with appEnv: AppEnvironment) {
        if window?.isVisible == true {
            window?.close()
            window = nil
            return
        }
        let content = FloatingCaptureContent()
            .environment(appEnv)
        let host = NSHostingController(rootView: content)
        let w = NSPanel(contentViewController: host)
        w.styleMask = [.borderless, .nonactivatingPanel]
        w.level = .floating
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = true
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

private struct FloatingCaptureContent: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            MacQuickAddView(onCommit: {
                NSApp.windows.first { $0.level == .floating }?.close()
            })
            .padding(12)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .frame(width: 600)
        .onExitCommand {
            NSApp.windows.first { $0.level == .floating }?.close()
        }
    }
}

// MARK: - Commands (full implementation)

struct MacCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Item…") {
                NotificationCenter.default.post(name: .leoOpenQuickAdd, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            Menu("New…") {
                Button("Task")     { NotificationCenter.default.post(name: .leoOpenQuickAdd, object: "task") }
                Button("Event")    { NotificationCenter.default.post(name: .leoOpenQuickAdd, object: "event") }
                Button("Reminder") { NotificationCenter.default.post(name: .leoOpenQuickAdd, object: "reminder") }
                Button("Alarm")    { NotificationCenter.default.post(name: .leoOpenQuickAdd, object: "alarm") }
            }
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

            Divider()
            // The views' `.refreshable` only draws a pull-down gesture, which macOS
            // doesn't have — so without this there is no way to refresh at all.
            Button("Refresh") {
                NotificationCenter.default.post(name: .leoRefreshRequested, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu("Item") {
            Button("Complete") {
                NotificationCenter.default.post(name: .leoCompleteSelectedItem, object: nil)
            }
            .keyboardShortcut(".", modifiers: .command)

            Button("Reschedule…") {
                NotificationCenter.default.post(name: .leoRescheduleSelectedItem, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Delete") {
                NotificationCenter.default.post(name: .leoDeleteSelectedItem, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
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
