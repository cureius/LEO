import SwiftUI

/// Root tab bar.
@MainActor
struct AppTabView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var selectedTab = 0
    @State private var pendingAlert: PendingReminderAlert? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayTabView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(0)

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(1)

            HealthTabView()
                .tabItem { Label("Health", systemImage: "heart.fill") }
                .tag(2)

            AssistantChatView()
                .tabItem { Label("Ask LEO", systemImage: "sparkles") }
                .tag(3)

            NavigationStack {
                SettingsRootView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(4)
        }
        .tint(Theme.Color.accent)
        // Listen for notification taps and show in-app Done/Snooze sheet
        .onReceive(NotificationCenter.default.publisher(for: .leoReminderTapped)) { note in
            pendingAlert = note.object as? PendingReminderAlert
        }
        .sheet(item: $pendingAlert) { alert in
            ReminderActionSheet(
                alert: alert,
                onDone: { @MainActor in
                    await handleDone(itemID: alert.id)
                    pendingAlert = nil
                },
                onSnooze: { @MainActor seconds in
                    await handleSnooze(itemID: alert.id, by: seconds)
                    pendingAlert = nil
                },
                onDismiss: { @MainActor in
                    pendingAlert = nil
                }
            )
        }
    }

    // MARK: - Actions

    private func handleDone(itemID: UUID) async {
        do {
            let items = try await appEnv.itemRepository.fetch(predicate: .byID(itemID))
            guard var item = items.first else { return }
            item.completion = .completed(at: .now)
            try await appEnv.itemRepository.update(item)
        } catch {}
        await appEnv.notificationManager.cancelAll(for: itemID)
    }

    private func handleSnooze(itemID: UUID, by seconds: TimeInterval) async {
        do {
            let items = try await appEnv.itemRepository.fetch(predicate: .byID(itemID))
            guard var item = items.first else { return }
            item.anchor = .point(Date.now.addingTimeInterval(seconds))
            try await appEnv.itemRepository.update(item)
        } catch {}
        await appEnv.notificationManager.cancelAll(for: itemID)
    }
}

#Preview {
    AppTabView()
        .environment(AppEnvironment(useInMemory: true))
}
