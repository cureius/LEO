import SwiftUI

/// Root tab bar.
@MainActor
struct AppTabView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayTabView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(0)

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(1)

            HabitsView()
                .tabItem { Label("Habits", systemImage: "repeat.circle.fill") }
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
    }

}

#Preview {
    AppTabView()
        .environment(AppEnvironment(useInMemory: true))
}
