import SwiftUI

/// Root tab bar.
@MainActor
struct AppTabView: View {
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        TabView {
            TodayTabView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(0)

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(1)

            HabitsView()
                .tabItem { Label("Habits", systemImage: "repeat.circle.fill") }
                .tag(2)

            NavigationStack {
                AssistantChatView(vm: makeAssistantVM())
            }
            .tabItem { Label("Ask LEO", systemImage: "sparkles") }
            .tag(3)

            NavigationStack {
                SettingsRootView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(4)
        }
        .tint(Theme.Color.accent)
    }

    private func makeAssistantVM() -> AssistantChatViewModel {
        let context = ToolContext(itemRepository: appEnv.itemRepository, calendar: .current)
        let toolRuntime = ToolRuntime(context: context)
        return AssistantChatViewModel(
            client: appEnv.claudeClient,
            toolRuntime: toolRuntime,
            itemRepository: appEnv.itemRepository
        )
    }
}

#Preview {
    AppTabView()
        .environment(AppEnvironment(useInMemory: true))
}
